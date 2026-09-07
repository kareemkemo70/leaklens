# -*- coding: utf-8 -*-
"""Pydantic v2 schemas for all request/response payloads."""

from pydantic import BaseModel, EmailStr, Field, field_validator, field_serializer
from typing import List, Optional, Any
from datetime import datetime, timezone


# ──────────────────────────────────────────────────────────────────────────────
# Prediction
# ──────────────────────────────────────────────────────────────────────────────

class PredictRequest(BaseModel):
    data: List[List[float]] = Field(
        ...,
        description="Time-series window of shape (48, N_sensors)"
    )
    forced_zone: Optional[str] = Field(
        None,
        description="Optional zone to assign the anomaly to, overriding the model's top sensors."
    )

    @field_validator("data")
    @classmethod
    def validate_shape(cls, v):
        if len(v) != 48:
            raise ValueError(f"Expected 48 timesteps, got {len(v)}")
        if not v or not isinstance(v[0], list):
            raise ValueError("data must be a 2D list (list of lists)")
        n = len(v[0])
        for row in v:
            if len(row) != n:
                raise ValueError("All timestep rows must have the same number of sensors")
        return v


class PredictResponse(BaseModel):
    is_anomaly: int                       # 0 or 1
    confidence: float
    mse: float
    threshold: float
    top_sensors: List[str]
    zone: str
    sensor_errors: List[float]
    message: str


# ──────────────────────────────────────────────────────────────────────────────
# Reports / Alerts
# ──────────────────────────────────────────────────────────────────────────────

class ReportCreate(BaseModel):
    zone: str = Field(..., min_length=1)
    description: str = Field(..., min_length=5, max_length=1000)
    severity: Optional[str] = "medium"
    user_id: Optional[int] = None


class ReportResponse(BaseModel):
    id: int
    zone: str
    description: str
    severity: str
    status: str
    user_id: Optional[int]
    user_name: Optional[str] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class AlertResponse(BaseModel):
    id: int
    is_anomaly: bool
    confidence: float
    mse: float
    threshold: float
    top_sensors: List[str]
    zone: str
    message: Optional[str] = None
    detected_at: datetime
    source: str

    model_config = {"from_attributes": True}

    @field_serializer('detected_at')
    def serialize_detected_at(self, dt: datetime, _info) -> str:
        # Always send UTC time with 'Z' suffix so mobile app parses correctly
        return dt.strftime('%Y-%m-%dT%H:%M:%S.%f') + 'Z'


class BroadcastRequest(BaseModel):
    zone: str
    message: str
    severity: str = "high"


# ──────────────────────────────────────────────────────────────────────────────
# Analytics
# ──────────────────────────────────────────────────────────────────────────────

class ZoneLeakCount(BaseModel):
    zone: str
    leak_count: int
    report_count: int
    total_incidents: int


class AnalyticsResponse(BaseModel):
    total_anomalies: int
    total_reports: int
    leaks_per_zone: List[ZoneLeakCount]
    most_affected_zone: str
    model_detections: int
    user_reports: int
    avg_confidence: float


class TimeseriesPoint(BaseModel):
    timestamp: str
    pressure: float
    flow: float
    is_anomaly: int
    zone: str


class TimeseriesResponse(BaseModel):
    series: List[TimeseriesPoint]
    total_points: int


# ──────────────────────────────────────────────────────────────────────────────
# Authentication
# ──────────────────────────────────────────────────────────────────────────────

class UserRegister(BaseModel):
    name: str = Field(..., min_length=2, max_length=100)
    address: str = Field(..., min_length=3)
    zone: str = Field(..., min_length=1)
    phone: str = Field(..., min_length=7, max_length=20)
    email: EmailStr
    password: str = Field(..., min_length=6)


class UserLogin(BaseModel):
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    password: str


class EngineerRegister(BaseModel):
    name: str = Field(..., min_length=2, max_length=100)
    engineer_id: str = Field(..., min_length=3, max_length=50)
    password: str = Field(..., min_length=6)


class EngineerLogin(BaseModel):
    engineer_id: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str                # "user" or "engineer"
    user_id: int
    name: str
    zone: Optional[str] = None


class UserResponse(BaseModel):
    id: int
    name: str
    email: str
    phone: str
    zone: str
    address: str
    created_at: datetime

    model_config = {"from_attributes": True}


class EngineerResponse(BaseModel):
    id: int
    name: str
    engineer_id: str
    created_at: datetime

    model_config = {"from_attributes": True}


# ──────────────────────────────────────────────────────────────────────────────
# Water Outages
# ──────────────────────────────────────────────────────────────────────────────

class OutageCreate(BaseModel):
    zone: str = Field(..., min_length=1)
    title: str = Field(..., min_length=3, max_length=200)
    description: Optional[str] = None
    start_time: datetime
    end_time: datetime


class OutageResponse(BaseModel):
    id: int
    zone: str
    title: str
    description: Optional[str]
    start_time: datetime
    end_time: datetime
    created_at: datetime
    is_cancelled: bool

    model_config = {"from_attributes": True}

    @field_serializer('start_time', 'end_time', 'created_at')
    def serialize_dt(self, dt: datetime, _info) -> str:
        return dt.strftime('%Y-%m-%dT%H:%M:%S') + 'Z'
