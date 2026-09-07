# -*- coding: utf-8 -*-
"""POST /report  and  GET /alerts"""

import logging
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from sqlalchemy import desc

from db.database import get_db
from db.models import Report, Anomaly
from schemas.schemas import ReportCreate, ReportResponse, AlertResponse, BroadcastRequest

logger = logging.getLogger(__name__)
router = APIRouter()


# ──────────────────────────────────────────────────────────────────────────────
# POST /report — user manually reports an issue
# ──────────────────────────────────────────────────────────────────────────────

@router.post(
    "/report",
    response_model=ReportResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Submit a manual water issue report",
)
async def create_report(payload: ReportCreate, db: Session = Depends(get_db)):
    """
    Users can manually report a water issue (e.g. visible leak, low pressure).
    The report is stored and visible to engineers via the /alerts feed.
    """
    valid_severities = {"low", "medium", "high"}
    if payload.severity not in valid_severities:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"severity must be one of {valid_severities}",
        )

    report = Report(
        user_id=payload.user_id,
        zone=payload.zone,
        description=payload.description,
        severity=payload.severity,
        status="pending",
    )
    db.add(report)
    db.commit()
    db.refresh(report)

    logger.info("Report #%d created — zone: %s, severity: %s",
                report.id, report.zone, report.severity)
    return report


# ──────────────────────────────────────────────────────────────────────────────
# GET /alerts — return detected anomalies (model + manual reports)
# ──────────────────────────────────────────────────────────────────────────────

@router.get(
    "/alerts",
    response_model=List[AlertResponse],
    summary="Get recent anomaly alerts",
)
async def get_alerts(
    limit: int = Query(50, ge=1, le=500),
    zone: Optional[str] = Query(None),
    anomaly_only: bool = Query(True, description="Return only anomaly=True records"),
    db: Session = Depends(get_db),
):
    """
    Returns model-detected anomalies ordered newest first.

    Query params
    - **limit**: max records (default 50)
    - **zone**: filter by zone (e.g. `Zone 2`)
    - **anomaly_only**: if true (default), only returns is_anomaly=True records
    """
    q = db.query(Anomaly).order_by(desc(Anomaly.detected_at))

    if anomaly_only:
        q = q.filter(Anomaly.is_anomaly == True)   # noqa: E712

    if zone:
        # Use case-insensitive and stripped matching for better reliability in demo/mobile
        zone_clean = zone.strip()
        q = q.filter(Anomaly.zone.ilike(f"%{zone_clean}%"))
        logger.info("🔍 Searching alerts for Zone: '%s'", zone_clean)

    alerts = q.limit(limit).all()
    logger.info("📡 Found %d alerts for this request", len(alerts))
    return alerts


# ──────────────────────────────────────────────────────────────────────────────
# GET /reports — list of manual user reports (for engineer view)
# ──────────────────────────────────────────────────────────────────────────────

@router.get(
    "/reports",
    response_model=List[ReportResponse],
    summary="Get all manual user reports",
)
async def get_reports(
    limit: int = Query(50, ge=1, le=500),
    zone: Optional[str] = Query(None),
    status_filter: Optional[str] = Query(None, alias="status"),
    user_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
):
    q = db.query(Report).order_by(desc(Report.created_at))

    if zone:
        q = q.filter(Report.zone == zone)
    if status_filter:
        q = q.filter(Report.status == status_filter)
    if user_id is not None:
        q = q.filter(Report.user_id == user_id)

    return q.limit(limit).all()


# ──────────────────────────────────────────────────────────────────────────────
# PATCH /reports/{id}/status — engineer updates report status
# ──────────────────────────────────────────────────────────────────────────────

@router.patch(
    "/reports/{report_id}/status",
    response_model=ReportResponse,
    summary="Update report status",
)
async def update_report_status(
    report_id: int,
    new_status: str = Query(..., regex="^(pending|investigating|resolved)$"),
    db: Session = Depends(get_db),
):
    report = db.query(Report).filter(Report.id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")

    report.status = new_status
    db.commit()
    db.refresh(report)
    return report


# ──────────────────────────────────────────────────────────────────────────────
# NOTIFICATIONS / LATEST
# ──────────────────────────────────────────────────────────────────────────────

@router.get(
    "/latest",
    response_model=Optional[AlertResponse],
    summary="Get the single most recent alert for a zone since a timestamp",
)
async def get_latest_alert(
    zone: str,
    since: datetime = Query(...),
    db: Session = Depends(get_db),
):
    """
    Used by the mobile app's background worker to check for new alerts.
    'since' should be in ISO 8601 format (e.g. 2024-05-01T12:00:00).
    """
    alert = (
        db.query(Anomaly)
        .filter(Anomaly.zone == zone)
        .filter(Anomaly.is_anomaly == True)   # noqa: E712
        .filter(Anomaly.detected_at > since)
        .order_by(desc(Anomaly.detected_at))
        .first()
    )
    return alert


@router.post(
    "/broadcast",
    response_model=AlertResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Manual broadcast alert from an engineer to a zone",
)
async def broadcast_alert(
    payload: BroadcastRequest,
    db: Session = Depends(get_db),
):
    """
    Creates a manual anomaly entry and sends a Firebase push notification
    to all users subscribed to the zone topic with the custom message.
    """
    alert = Anomaly(
        is_anomaly=True,
        confidence=1.0,
        mse=99.0,
        threshold=0.1,
        top_sensors=["MANUAL"],
        zone=payload.zone,
        sensor_errors=[],
        source="manual",
        message=payload.message,
    )
    db.add(alert)
    db.commit()
    db.refresh(alert)

    logger.info("📡 Broadcast alert saved to DB — zone: %s, message: %s", alert.zone, payload.message)

    # ── Send Firebase push notification ──────────────────────────────────────
    try:
        import firebase_admin
        from firebase_admin import messaging

        topic_name = str(payload.zone).replace(" ", "_")

        fcm_msg = messaging.Message(
            notification=messaging.Notification(
                title=f"📢 LeakLens Alert — {payload.zone}",
                body=payload.message,
            ),
            data={
                "zone":     str(payload.zone),
                "message":  payload.message,
                "severity": payload.severity,
                "type":     "broadcast_alert",
            },
            topic=topic_name,
        )
        response = messaging.send(fcm_msg)
        logger.info("✅ Firebase broadcast sent to topic '%s': %s", topic_name, response)
    except Exception as exc:
        logger.warning("⚠️ Firebase broadcast failed (non-fatal): %s", exc)

    return alert


# ──────────────────────────────────────────────────────────────────────────────
# DELETE /alerts/{id} — engineer permanently deletes an anomaly alert
# ──────────────────────────────────────────────────────────────────────────────

@router.delete(
    "/alerts/{alert_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Permanently delete an anomaly alert",
)
async def delete_alert(alert_id: int, db: Session = Depends(get_db)):
    alert = db.query(Anomaly).filter(Anomaly.id == alert_id).first()
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")
    db.delete(alert)
    db.commit()
    logger.info("🗑️ Alert #%d deleted permanently", alert_id)


# ──────────────────────────────────────────────────────────────────────────────
# DELETE /reports/{id} — engineer permanently deletes a user report
# ──────────────────────────────────────────────────────────────────────────────

@router.delete(
    "/reports/{report_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Permanently delete a user report",
)
async def delete_report(report_id: int, db: Session = Depends(get_db)):
    report = db.query(Report).filter(Report.id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
    db.delete(report)
    db.commit()
    logger.info("🗑️ Report #%d deleted permanently", report_id)


# ──────────────────────────────────────────────────────────────────────────────
# POST /reset-data — wipes anomalies, reports, sensor_logs (keeps accounts)
# ──────────────────────────────────────────────────────────────────────────────

@router.post(
    "/reset-data",
    summary="Reset all operational data (keeps user/engineer accounts)",
)
async def reset_data(db: Session = Depends(get_db)):
    from db.models import SensorLog, WaterOutage
    deleted_anomalies = db.query(Anomaly).delete()
    deleted_reports   = db.query(Report).delete()
    deleted_logs      = db.query(SensorLog).delete()
    deleted_outages   = db.query(WaterOutage).delete()
    db.commit()
    logger.warning(
        "⚠️ Data reset: %d anomalies, %d reports, %d sensor_logs, %d outages deleted",
        deleted_anomalies, deleted_reports, deleted_logs, deleted_outages,
    )
    return {
        "message": "All operational data cleared successfully",
        "deleted": {
            "anomalies": deleted_anomalies,
            "reports": deleted_reports,
            "sensor_logs": deleted_logs,
            "outages": deleted_outages,
        },
    }
