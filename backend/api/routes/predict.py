# -*- coding: utf-8 -*-
"""POST /predict — core anomaly detection endpoint."""

import logging
from datetime import datetime

import numpy as np
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from db.database import get_db
from db.models import Anomaly, SensorLog
from model.predictor import predictor
from schemas.schemas import PredictRequest, PredictResponse

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post(
    "/predict",
    response_model=PredictResponse,
    summary="Run water leakage detection on a sensor window",
)
async def predict(request: PredictRequest, db: Session = Depends(get_db)):
    """
    Accepts a time-series window of shape **(48 × N)** and returns:

    - **is_anomaly**: 0 or 1
    - **confidence**: how far above/below threshold (0–1)
    - **mse**: mean reconstruction error
    - **threshold**: 95th-percentile baseline
    - **top_sensors**: top 3 sensors by error
    - **zone**: most affected network zone
    - **sensor_errors**: per-sensor error list (length N)
    """
    data_np = np.array(request.data, dtype=np.float32)   # (48, N)

    logger.info("Predict called — shape: %s", data_np.shape)

    try:
        result = predictor.predict(data_np)
        if request.forced_zone:
            result["zone"] = request.forced_zone
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                            detail=str(exc))
    except Exception as exc:
        logger.exception("Prediction failed")
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                            detail=f"Model inference error: {exc}")

    # ── Persist to DB (fire-and-forget style, don't fail request) ─────────
    try:
        anomaly_rec = Anomaly(
            is_anomaly=bool(result["is_anomaly"]),
            confidence=result["confidence"],
            mse=result["mse"],
            threshold=result["threshold"],
            top_sensors=result["top_sensors"],
            zone=result["zone"],
            sensor_errors=result["sensor_errors"],
            source="model",
            detected_at=datetime.utcnow(),
        )
        db.add(anomaly_rec)

        log_rec = SensorLog(
            num_sensors=data_np.shape[1],
            mean_value=float(np.mean(data_np)),
            std_value=float(np.std(data_np)),
            anomaly_detected=bool(result["is_anomaly"]),
            zone=result["zone"],
        )
        db.add(log_rec)
        db.commit()
    except Exception as exc:
        logger.warning("DB write failed (non-fatal): %s", exc)
        db.rollback()

    try:
        if result["is_anomaly"]:
            import firebase_admin
            from firebase_admin import messaging

            # Format zone string for FCM topic (remove spaces, e.g., 'Zone 1' -> 'Zone_1')
            topic_name = str(result["zone"]).replace(" ", "_")

            # DATA-ONLY message: no `notification` field.
            # Android delivers data-only messages to the app's background handler
            # even when the app is killed. The handler creates the local notification
            # itself, giving us full control over sound/channel/content.
            # Messages WITH a `notification` field are shown by Android automatically
            # and bypass our handler — that caused the "notification outside app only" bug.
            fcm_msg = messaging.Message(
                data={
                    "type":        "anomaly_alert",
                    "title":       "\u26a0\ufe0f Water Leak Alert",
                    "body":        f"High-confidence leak detected in {result['zone']}. "
                                   f"Immediate attention required.",
                    "zone":        str(result["zone"]),
                    "confidence":  str(result["confidence"]),
                    "top_sensors": ",".join(result["top_sensors"]),
                },
                android=messaging.AndroidConfig(priority="high"),
                condition=f"'{topic_name}' in topics || 'engineers' in topics",
            )
            response = messaging.send(fcm_msg)
            logger.info("FCM Broadcast sent to condition: %s", response)
    except Exception as exc:
        logger.error("Failed to send FCM broadcast: %s", exc)

    message = (
        f"⚠️ Leak detected in {result['zone']} with "
        f"{result['confidence']*100:.1f}% confidence"
        if result["is_anomaly"]
        else "✅ No anomaly detected — system operating normally"
    )

    return PredictResponse(**result, message=message)
