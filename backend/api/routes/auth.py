# -*- coding: utf-8 -*-
"""Authentication routes — user and engineer register / login."""

import logging
import os
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from passlib.context import CryptContext
from jose import JWTError, jwt

from db.database import get_db
from db.models import User, Engineer
from schemas.schemas import (
    UserRegister, UserLogin, UserResponse,
    EngineerRegister, EngineerLogin, EngineerResponse,
    TokenResponse,
)

logger = logging.getLogger(__name__)
router = APIRouter()

# ── JWT config ────────────────────────────────────────────────────────────────
SECRET_KEY = os.getenv("SECRET_KEY", "change-me-in-production-super-secret-key")
ALGORITHM = os.getenv("ALGORITHM", "HS256")
EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "10080"))  # 7 days

pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")


def _hash(plain: str) -> str:
    # bcrypt has a 72-character limit; truncate to avoid ValueError
    return pwd_ctx.hash(plain[:72])


def _verify(plain: str, hashed: str) -> bool:
    return pwd_ctx.verify(plain, hashed)


def _create_token(data: dict, expires_minutes: int = EXPIRE_MINUTES) -> str:
    payload = data.copy()
    payload["exp"] = datetime.utcnow() + timedelta(minutes=expires_minutes)
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


# ─────────────────────────────────────────────
# USER — Register
# ─────────────────────────────────────────────

@router.post(
    "/user/register",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new user account",
)
async def register_user(payload: UserRegister, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.email == payload.email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered",
        )

    user = User(
        name=payload.name,
        address=payload.address,
        zone=payload.zone,
        phone=payload.phone,
        email=payload.email,
        password_hash=_hash(payload.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    token = _create_token({"sub": str(user.id), "role": "user"})
    logger.info("User registered: %s (id=%d)", user.email, user.id)

    return TokenResponse(
        access_token=token,
        role="user",
        user_id=user.id,
        name=user.name,
        zone=user.zone,
    )


# ─────────────────────────────────────────────
# USER — Login
# ─────────────────────────────────────────────

@router.post(
    "/user/login",
    response_model=TokenResponse,
    summary="Login with email or phone + password",
)
async def login_user(payload: UserLogin, db: Session = Depends(get_db)):
    user: Optional[User] = None

    if payload.email:
        user = db.query(User).filter(User.email == payload.email).first()
    elif payload.phone:
        user = db.query(User).filter(User.phone == payload.phone).first()

    if not user or not _verify(payload.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
        )
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account is deactivated")

    token = _create_token({"sub": str(user.id), "role": "user"})
    return TokenResponse(
        access_token=token,
        role="user",
        user_id=user.id,
        name=user.name,
        zone=user.zone,
    )


# ─────────────────────────────────────────────
# ENGINEER — Register
# ─────────────────────────────────────────────

@router.post(
    "/engineer/register",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new engineer account",
)
async def register_engineer(payload: EngineerRegister, db: Session = Depends(get_db)):
    existing = (
        db.query(Engineer)
        .filter(Engineer.engineer_id == payload.engineer_id)
        .first()
    )
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Engineer ID already registered",
        )

    engineer = Engineer(
        name=payload.name,
        engineer_id=payload.engineer_id,
        password_hash=_hash(payload.password),
    )
    db.add(engineer)
    db.commit()
    db.refresh(engineer)

    token = _create_token({"sub": str(engineer.id), "role": "engineer"})
    logger.info("Engineer registered: %s (id=%d)", engineer.engineer_id, engineer.id)

    return TokenResponse(
        access_token=token,
        role="engineer",
        user_id=engineer.id,
        name=engineer.name,
    )


# ─────────────────────────────────────────────
# ENGINEER — Login
# ─────────────────────────────────────────────

@router.post(
    "/engineer/login",
    response_model=TokenResponse,
    summary="Login with engineer ID + password",
)
async def login_engineer(payload: EngineerLogin, db: Session = Depends(get_db)):
    engineer = (
        db.query(Engineer)
        .filter(Engineer.engineer_id == payload.engineer_id)
        .first()
    )
    if not engineer or not _verify(payload.password, engineer.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid engineer credentials",
        )
    if not engineer.is_active:
        raise HTTPException(status_code=403, detail="Account is deactivated")

    token = _create_token({"sub": str(engineer.id), "role": "engineer"})
    return TokenResponse(
        access_token=token,
        role="engineer",
        user_id=engineer.id,
        name=engineer.name,
    )


# ─────────────────────────────────────────────
# GET /me — verify token & return profile
# ─────────────────────────────────────────────

@router.get(
    "/me",
    summary="Verify token and return current profile",
)
async def get_me(
    token: str,
    db: Session = Depends(get_db),
):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = int(payload["sub"])
        role = payload["role"]
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    if role == "user":
        record = db.query(User).filter(User.id == user_id).first()
        if not record:
            raise HTTPException(status_code=404, detail="User not found")
        return {"role": "user", "id": record.id, "name": record.name,
                "email": record.email, "zone": record.zone}
    else:
        record = db.query(Engineer).filter(Engineer.id == user_id).first()
        if not record:
            raise HTTPException(status_code=404, detail="Engineer not found")
        return {"role": "engineer", "id": record.id,
                "name": record.name, "engineer_id": record.engineer_id}
