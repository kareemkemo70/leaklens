# -*- coding: utf-8 -*-
"""Water Outage scheduling — POST /outages, GET /outages, DELETE /outages/{id}

Background alarm dispatcher
---------------------------
When an outage is created, TWO FCM messages are sent:

1. **Immediately** (type=outage_scheduled): Lets the phone show a confirmation
   notification and pre-register a local alarm as a backup.

2. **At the outage start time** (type=outage_starting): Sent by a background
   thread that checks every 20 seconds for outages that are starting.  The
   phone's background FCM handler shows an IMMEDIATE full-screen alarm
   notification — no client-side scheduling needed.

CRITICAL: Both messages are **data-only** (no `notification` field).
On Android, if an FCM message contains a `notification` field and the app is
killed, Android shows it automatically and NEVER calls `onBackgroundMessage`.
Data-only messages ALWAYS trigger `onBackgroundMessage`, even on a killed app.
"""

import logging
import threading
import time as _time
from datetime import datetime, timedelta
from typing import List, Optional, Set

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from sqlalchemy import desc

from db.database import get_db, SessionLocal
from db.models import WaterOutage
from schemas.schemas import OutageCreate, OutageResponse

logger = logging.getLogger(__name__)
router = APIRouter()

# ── Track which outages we've already dispatched start-time FCMs for ─────────
_dispatched_outage_ids: Set[int] = set()
_dispatcher_started = False


def _send_fcm_for_outage(outage_zone: str, outage_id: int, outage_title: str,
                         start_time: datetime, end_time: datetime,
                         msg_type: str):
    """Send a DATA-ONLY FCM message (no notification field) to a zone topic.

    msg_type is either 'outage_scheduled' (at creation) or
    'outage_starting' (at the actual start time).
    """
    try:
        import firebase_admin  # noqa: F401
        from firebase_admin import messaging

        topic_name = str(outage_zone).replace(" ", "_")
        start_iso = start_time.strftime('%Y-%m-%dT%H:%M:%S') + 'Z'
        end_iso = end_time.strftime('%Y-%m-%dT%H:%M:%S') + 'Z'

        # ⚠️ NO `notification=` field — this is CRITICAL.
        # Data-only messages ALWAYS trigger onBackgroundMessage on killed apps.
        fcm_msg = messaging.Message(
            data={
                "type":         msg_type,
                "outage_id":    str(outage_id),
                "outage_title": outage_title,
                "start_time":   start_iso,
                "end_time":     end_iso,
                "zone":         outage_zone,
            },
            android=messaging.AndroidConfig(
                priority="high",
                # TTL = 0 means deliver immediately or drop — no stale alarms
                ttl=timedelta(seconds=0) if msg_type == "outage_starting" else timedelta(hours=24),
            ),
            topic=topic_name,
        )
        response = messaging.send(fcm_msg)
        logger.info("✅ FCM [%s] sent to topic '%s': %s", msg_type, topic_name, response)
    except Exception as exc:
        logger.warning("⚠️ FCM [%s] failed (non-fatal): %s", msg_type, exc)


def _outage_alarm_dispatcher():
    """Background thread: every 20s, check for outages starting now and send FCM.

    This runs in a daemon thread so it dies when the main process exits.
    """
    logger.info("🔔 Outage alarm dispatcher thread started (checking every 20s)")
    while True:
        try:
            db = SessionLocal()
            now = datetime.utcnow()
            # Find outages starting within the next 30 seconds that we haven't
            # dispatched yet.
            window = now + timedelta(seconds=30)
            outages = (
                db.query(WaterOutage)
                .filter(WaterOutage.is_cancelled == False)  # noqa: E712
                .filter(WaterOutage.start_time <= window)
                .filter(WaterOutage.start_time >= now - timedelta(seconds=30))
                .all()
            )
            for o in outages:
                if o.id not in _dispatched_outage_ids:
                    _dispatched_outage_ids.add(o.id)
                    logger.info("🔔 Dispatching start-time alarm for outage #%d: %s", o.id, o.title)
                    _send_fcm_for_outage(
                        outage_zone=o.zone,
                        outage_id=o.id,
                        outage_title=o.title,
                        start_time=o.start_time,
                        end_time=o.end_time,
                        msg_type="outage_starting",
                    )
            db.close()

            # Prune old IDs to avoid unbounded memory growth
            if len(_dispatched_outage_ids) > 500:
                _dispatched_outage_ids.clear()

        except Exception as exc:
            logger.error("⚠️ Alarm dispatcher error: %s", exc)

        _time.sleep(20)


def _ensure_dispatcher_running():
    """Starts the background alarm dispatcher thread if not already running."""
    global _dispatcher_started
    if not _dispatcher_started:
        _dispatcher_started = True
        t = threading.Thread(target=_outage_alarm_dispatcher, daemon=True,
                             name="outage-alarm-dispatcher")
        t.start()


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post(
    "/outages",
    response_model=OutageResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Engineer creates a water outage schedule for a zone",
)
async def create_outage(payload: OutageCreate, db: Session = Depends(get_db)):
    if payload.end_time <= payload.start_time:
        raise HTTPException(
            status_code=422, detail="end_time must be after start_time"
        )
    outage = WaterOutage(
        zone=payload.zone,
        title=payload.title,
        description=payload.description,
        start_time=payload.start_time,
        end_time=payload.end_time,
    )
    db.add(outage)
    db.commit()
    db.refresh(outage)
    logger.info("📅 Outage created for %s: %s (%s → %s)",
                outage.zone, outage.title, outage.start_time, outage.end_time)

    # ── FCM #1: Immediate "outage_scheduled" data-only push ──────────────────
    # Phone will show a confirmation notification and pre-register a local alarm
    _send_fcm_for_outage(
        outage_zone=outage.zone,
        outage_id=outage.id,
        outage_title=outage.title,
        start_time=outage.start_time,
        end_time=outage.end_time,
        msg_type="outage_scheduled",
    )

    # ── Ensure the background dispatcher is running ──────────────────────────
    # It will send FCM #2 (outage_starting) at the actual start time.
    _ensure_dispatcher_running()

    return outage


@router.get(
    "/outages",
    response_model=List[OutageResponse],
    summary="Get upcoming (or all) water outage schedules",
)
async def get_outages(
    zone: Optional[str] = Query(None),
    include_past: bool = Query(False),
    db: Session = Depends(get_db),
):
    from datetime import datetime
    q = db.query(WaterOutage).filter(WaterOutage.is_cancelled == False)  # noqa
    if zone:
        q = q.filter(WaterOutage.zone == zone)
    if not include_past:
        q = q.filter(WaterOutage.end_time >= datetime.utcnow())
    outages = q.order_by(WaterOutage.start_time).all()
    return outages


@router.delete(
    "/outages/{outage_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Cancel / delete a water outage entry",
)
async def delete_outage(outage_id: int, db: Session = Depends(get_db)):
    outage = db.query(WaterOutage).filter(WaterOutage.id == outage_id).first()
    if not outage:
        raise HTTPException(status_code=404, detail="Outage not found")
    db.delete(outage)
    db.commit()
    # Remove from dispatched set so it won't be sent
    _dispatched_outage_ids.discard(outage_id)
    logger.info("🗑️ Outage #%d deleted", outage_id)
