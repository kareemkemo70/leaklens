# -*- coding: utf-8 -*-
"""GET /analytics  and  GET /timeseries"""

import logging
import random
from datetime import datetime, timedelta
from collections import defaultdict
from typing import List

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, desc

from db.database import get_db
from db.models import Anomaly, Report, SensorLog
from schemas.schemas import (
    AnalyticsResponse, ZoneLeakCount,
    TimeseriesResponse, TimeseriesPoint,
)

logger = logging.getLogger(__name__)
router = APIRouter()

ALL_ZONES = ["Zone 1", "Zone 2", "Zone 3", "Zone 4", "Zone 5"]


# ──────────────────────────────────────────────────────────────────────────────
# GET /analytics
# ──────────────────────────────────────────────────────────────────────────────

@router.get(
    "/analytics",
    response_model=AnalyticsResponse,
    summary="Aggregated leak analytics across all zones",
)
async def get_analytics(
    days: int = Query(30, ge=1, le=365, description="Look-back period in days"),
    db: Session = Depends(get_db),
):
    """
    Returns:
    - Total anomalies detected by the model
    - Total manual user reports
    - Leak + report counts broken down by zone
    - Most affected zone
    - Average model confidence across detections
    """
    since = datetime.utcnow() - timedelta(days=days)

    # ── Anomaly counts ──────────────────────────────────────────────────────
    anomaly_rows = (
        db.query(Anomaly.zone, func.count(Anomaly.id).label("cnt"))
        .filter(Anomaly.is_anomaly == True, Anomaly.detected_at >= since)   # noqa
        .group_by(Anomaly.zone)
        .all()
    )
    anomaly_by_zone = {row.zone: row.cnt for row in anomaly_rows}
    total_anomalies = sum(anomaly_by_zone.values())

    # Average confidence
    avg_conf_row = (
        db.query(func.avg(Anomaly.confidence))
        .filter(Anomaly.is_anomaly == True, Anomaly.detected_at >= since)   # noqa
        .scalar()
    )
    avg_confidence = round(float(avg_conf_row or 0.0), 4)

    # ── Report counts ────────────────────────────────────────────────────────
    report_rows = (
        db.query(Report.zone, func.count(Report.id).label("cnt"))
        .filter(Report.created_at >= since)
        .group_by(Report.zone)
        .all()
    )
    report_by_zone = {row.zone: row.cnt for row in report_rows}
    total_reports = sum(report_by_zone.values())

    # ── Per-zone summary ─────────────────────────────────────────────────────
    leaks_per_zone: List[ZoneLeakCount] = []
    for zone in ALL_ZONES:
        lc = anomaly_by_zone.get(zone, 0)
        rc = report_by_zone.get(zone, 0)
        leaks_per_zone.append(
            ZoneLeakCount(
                zone=zone,
                leak_count=lc,
                report_count=rc,
                total_incidents=lc + rc,
            )
        )

    # Sort descending by total incidents
    leaks_per_zone.sort(key=lambda z: z.total_incidents, reverse=True)
    most_affected = leaks_per_zone[0].zone if leaks_per_zone else "N/A"

    # If DB is empty (first run) — return demo data
    if total_anomalies == 0 and total_reports == 0:
        return _demo_analytics()

    return AnalyticsResponse(
        total_anomalies=total_anomalies,
        total_reports=total_reports,
        leaks_per_zone=leaks_per_zone,
        most_affected_zone=most_affected,
        model_detections=total_anomalies,
        user_reports=total_reports,
        avg_confidence=avg_confidence,
    )


def _demo_analytics() -> AnalyticsResponse:
    """Return synthetic analytics when the DB has no data yet."""
    demo_zones = [
        ZoneLeakCount(zone="Zone 2", leak_count=14, report_count=5, total_incidents=19),
        ZoneLeakCount(zone="Zone 4", leak_count=9,  report_count=7, total_incidents=16),
        ZoneLeakCount(zone="Zone 1", leak_count=6,  report_count=3, total_incidents=9),
        ZoneLeakCount(zone="Zone 3", leak_count=4,  report_count=2, total_incidents=6),
        ZoneLeakCount(zone="Zone 5", leak_count=2,  report_count=0, total_incidents=2),
    ]
    return AnalyticsResponse(
        total_anomalies=35,
        total_reports=17,
        leaks_per_zone=demo_zones,
        most_affected_zone="Zone 2",
        model_detections=35,
        user_reports=17,
        avg_confidence=0.7843,
    )


# ──────────────────────────────────────────────────────────────────────────────
# GET /timeseries
# ──────────────────────────────────────────────────────────────────────────────

@router.get(
    "/timeseries",
    response_model=TimeseriesResponse,
    summary="Pressure / flow time-series with anomaly labels",
)
async def get_timeseries(
    hours: int = Query(24, ge=1, le=168, description="Hours of history to return"),
    zone: str = Query("all"),
    db: Session = Depends(get_db),
):
    """
    Returns a list of time-series points with:
    - pressure (simulated from sensor log mean)
    - flow (derived)
    - is_anomaly label
    - zone
    """
    since = datetime.utcnow() - timedelta(hours=hours)

    logs = (
        db.query(SensorLog)
        .filter(SensorLog.timestamp >= since)
        .order_by(SensorLog.timestamp)
        .all()
    )

    if not logs:
        # Generate demo time-series (48 data points)
        return _demo_timeseries(hours)

    series: List[TimeseriesPoint] = []
    for log in logs:
        pressure = round(float(log.mean_value or 0) * 2.5 + 5.0, 3)
        flow = round(abs(float(log.std_value or 0)) * 1.8 + 2.0, 3)
        series.append(
            TimeseriesPoint(
                timestamp=log.timestamp.isoformat(),
                pressure=pressure,
                flow=flow,
                is_anomaly=int(log.anomaly_detected),
                zone=log.zone or "Unknown",
            )
        )

    return TimeseriesResponse(series=series, total_points=len(series))


def _demo_timeseries(hours: int) -> TimeseriesResponse:
    """Synthetic realistic time-series for demo / first-run."""
    rng = random.Random(42)
    n_points = min(hours * 6, 288)   # one point per 10 min, max 288
    now = datetime.utcnow()
    series = []

    pressure = 5.5
    for i in range(n_points):
        ts = now - timedelta(minutes=(n_points - i) * 10)
        # Inject a simulated leak ~30% through the series
        if n_points * 0.28 < i < n_points * 0.38:
            pressure -= rng.uniform(0.02, 0.06)
            is_anomaly = 1 if pressure < 4.8 else 0
        else:
            pressure += rng.uniform(-0.05, 0.07)
            pressure = max(3.5, min(7.0, pressure))
            is_anomaly = 0

        flow = pressure * rng.uniform(0.4, 0.6) + rng.uniform(-0.1, 0.1)
        zone = rng.choice(ALL_ZONES)

        series.append(
            TimeseriesPoint(
                timestamp=ts.isoformat(),
                pressure=round(pressure, 3),
                flow=round(flow, 3),
                is_anomaly=is_anomaly,
                zone=zone,
            )
        )

    return TimeseriesResponse(series=series, total_points=len(series))
