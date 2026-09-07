# -*- coding: utf-8 -*-
"""SQLAlchemy database engine and session factory."""

from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import os
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./water_leak.db")

# SQLite needs check_same_thread=False for FastAPI's thread pool
connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

engine = create_engine(
    DATABASE_URL,
    connect_args=connect_args,
    echo=False,
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    """Dependency: yield a DB session and close it after request."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
