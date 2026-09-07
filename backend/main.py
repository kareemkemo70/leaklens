# -*- coding: utf-8 -*-
"""
Water Leakage Detection API — FastAPI entry point.
Run with:  uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""

import logging
import os
import time
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

load_dotenv()

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("water_leak")

# ── Import routers AFTER dotenv so env vars are available ────────────────────
from db.database import engine, Base           # noqa: E402
from api.routes import predict, reports, analytics, auth, simulate, outages   # noqa: E402


# ── Lifespan: create DB tables on startup ────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("🚀 Starting Water Leakage Detection API …")
    Base.metadata.create_all(bind=engine)
    logger.info("✅ Database tables ready")

    # Safe migration: add 'message' column to anomalies if it doesn't exist yet
    try:
        with engine.connect() as conn:
            conn.execute(__import__('sqlalchemy').text(
                "ALTER TABLE anomalies ADD COLUMN message TEXT"
            ))
            conn.commit()
            logger.info("✅ Migration: added 'message' column to anomalies")
    except Exception:
        pass  # Column already exists — this is the normal case after first run

    # Initialize Firebase Admin
    try:
        import firebase_admin
        from firebase_admin import credentials
        cred = credentials.Certificate("firebase-adminsdk.json")
        firebase_admin.initialize_app(cred)
        logger.info("✅ Firebase Admin initialized")
    except Exception as exc:
        logger.error(f"⚠️ Failed to initialize Firebase Admin: {exc}")

    # Warm up predictor singleton (loads model if available)
    from model.predictor import predictor   # noqa: F401
    logger.info("✅ Predictor initialised — using %s",
                "real model" if predictor.model else "mock predictor")

    # Seed default Engineer if none exist
    from db.database import SessionLocal
    from db.models import Engineer
    from api.routes.auth import _hash
    
    with SessionLocal() as db:
        if db.query(Engineer).count() == 0:
            default_engineer = Engineer(
                engineer_id="ENG-001",
                name="Admin Engineer",
                password_hash=_hash("admin123"),
            )
            db.add(default_engineer)
            db.commit()
            logger.info("👷 Seeded default engineer: ENG-001 / admin123")

    # Start the outage alarm dispatcher background thread
    from api.routes.outages import _ensure_dispatcher_running
    _ensure_dispatcher_running()

    yield
    logger.info("🛑 Shutting down")


# ── FastAPI app ───────────────────────────────────────────────────────────────

app = FastAPI(
    title="💧 Water Leakage Detection API",
    description=(
        "AI-powered water network anomaly detection using a Conv1D Autoencoder. "
        "Feed 48-timestep sensor windows to `/predict` and get instant leak alerts."
    ),
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# ── CORS ──────────────────────────────────────────────────────────────────────

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # Lock down in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Request timing middleware ─────────────────────────────────────────────────

@app.middleware("http")
async def add_process_time_header(request: Request, call_next):
    t0 = time.perf_counter()
    response = await call_next(request)
    elapsed = round((time.perf_counter() - t0) * 1000, 2)
    response.headers["X-Process-Time-Ms"] = str(elapsed)
    return response


# ── Global error handler ──────────────────────────────────────────────────────

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled exception on %s %s", request.method, request.url)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error", "path": str(request.url)},
    )


# ── Routers ───────────────────────────────────────────────────────────────────

PREFIX = "/api/v1"

app.include_router(predict.router,   prefix=PREFIX, tags=["🔍 Prediction"])
app.include_router(reports.router,   prefix=PREFIX, tags=["📢 Reports & Alerts"])
app.include_router(analytics.router, prefix=PREFIX, tags=["📊 Analytics"])
app.include_router(auth.router,      prefix=f"{PREFIX}/auth", tags=["🔐 Authentication"])
app.include_router(simulate.router,  prefix=PREFIX, tags=["🧪 Simulator"])
app.include_router(outages.router,   prefix=PREFIX, tags=["📅 Water Outages"])

# ── Static Dashboard (must be mounted AFTER all API routes) ───────────────────
import pathlib
_dashboard_dir = pathlib.Path(__file__).parent.parent / "dashboard"
if _dashboard_dir.exists():
    app.mount("/dashboard", StaticFiles(directory=str(_dashboard_dir), html=True), name="dashboard")


# ── Health / root ─────────────────────────────────────────────────────────────

@app.get("/", include_in_schema=False)
async def root():
    return {"message": "💧 LeakLens API", "docs": "/docs"}


@app.get("/health", tags=["System"])
async def health():
    from model.predictor import predictor
    return {
        "status": "ok",
        "version": "1.0.0",
        "model_loaded": predictor.model is not None,
        "num_sensors": predictor.num_sensors,
        "window_size": predictor.window_size,
        "threshold": predictor.threshold,
    }
