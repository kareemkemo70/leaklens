# -*- coding: utf-8 -*-
"""SQLAlchemy ORM models — tables: users, engineers, reports, anomalies, sensor_logs."""

from sqlalchemy import (
    Column, Integer, String, Float, DateTime, JSON,
    Boolean, Text, ForeignKey
)
from sqlalchemy.orm import relationship
from datetime import datetime
from db.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    address = Column(String(200))
    zone = Column(String(50))
    phone = Column(String(20))
    email = Column(String(100), unique=True, index=True, nullable=False)
    password_hash = Column(String(200), nullable=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    reports = relationship("Report", back_populates="user", cascade="all, delete-orphan")


class Engineer(Base):
    __tablename__ = "engineers"

    id = Column(Integer, primary_key=True, index=True)
    engineer_id = Column(String(50), unique=True, index=True, nullable=False)
    name = Column(String(100), nullable=False)
    password_hash = Column(String(200), nullable=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)


class Report(Base):
    __tablename__ = "reports"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    zone = Column(String(50), nullable=False)
    description = Column(Text, nullable=False)
    # pending | investigating | resolved
    status = Column(String(20), default="pending", nullable=False)
    severity = Column(String(20), default="medium")   # low | medium | high
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    user = relationship("User", back_populates="reports")

    @property
    def user_name(self):
        return self.user.name if self.user else None


class Anomaly(Base):
    __tablename__ = "anomalies"

    id = Column(Integer, primary_key=True, index=True)
    is_anomaly = Column(Boolean, default=False, nullable=False)
    confidence = Column(Float, nullable=False)
    mse = Column(Float, nullable=False)
    threshold = Column(Float, nullable=False)
    top_sensors = Column(JSON)     # ["n33", "n28", "n74"]
    zone = Column(String(50))
    sensor_errors = Column(JSON)   # list of per-sensor MSE values
    source = Column(String(50), default="model")   # model | manual
    message = Column(Text, nullable=True)          # custom broadcast message
    detected_at = Column(DateTime, default=datetime.utcnow, index=True)


class SensorLog(Base):
    __tablename__ = "sensor_logs"

    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime, default=datetime.utcnow, index=True)
    num_sensors = Column(Integer, nullable=False)
    mean_value = Column(Float)
    std_value = Column(Float)
    anomaly_detected = Column(Boolean, default=False)
    zone = Column(String(50))
    logged_at = Column(DateTime, default=datetime.utcnow)


class WaterOutage(Base):
    __tablename__ = "water_outages"

    id = Column(Integer, primary_key=True, index=True)
    zone = Column(String(50), nullable=False, index=True)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    start_time = Column(DateTime, nullable=False)
    end_time = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    is_cancelled = Column(Boolean, default=False)
