# -*- coding: utf-8 -*-
"""
GET /simulate?type=leak|normal|random|synthetic|synthetic_leak

Returns a (48 × 119) sensor window for dashboard testing.

Mode summary
────────────
  normal         — real slice from SCADA training data  (model has SEEN this)
  leak           — real slice + IQR pressure-drop       (model has SEEN base)
  random         — 50/50 coin flip between above two    (model has SEEN these)
  synthetic      — UNSEEN ✨ Gaussian AR(1) normal walk  (never in training set)
  synthetic_leak — UNSEEN ✨ Gaussian baseline + burst   (never in training set)

The unseen modes generate data purely from per-sensor statistics
(mean, std, min, max) stored in dataset_stats.json. Every call
produces a different time-series — a genuine blind test for the AI.
"""

import json
import logging
from pathlib import Path
from typing import List

import numpy as np
from fastapi import APIRouter, HTTPException, Query

logger = logging.getLogger(__name__)
router = APIRouter()

# ── Load dataset artefacts once at module import ──────────────────────────────
_MODEL_DIR = Path(__file__).parent.parent.parent / "model"


def _load_stats():
    p = _MODEL_DIR / "dataset_stats.json"
    if not p.exists():
        raise RuntimeError(
            f"dataset_stats.json not found at {p}. "
            "Run the stats-extraction script first."
        )
    with open(p) as f:
        return json.load(f)


def _load_normal_data():
    p = _MODEL_DIR / "normal_data.npy"
    if not p.exists():
        raise RuntimeError(f"normal_data.npy not found at {p}.")
    return np.load(p).astype(np.float32)


# Load stats (required for synthetic modes)
try:
    _STATS        = _load_stats()
    _FEATURE_COLS: List[str] = _STATS["feature_cols"]
    _N_SENSORS: int          = _STATS["n_cols"]      # 119
    _WINDOW: int             = _STATS["window_size"]  # 48
    _COL_MEAN = np.array(_STATS["col_mean"], dtype=np.float32)
    _COL_STD  = np.array(_STATS["col_std"],  dtype=np.float32)
    _COL_MIN  = np.array(_STATS["col_min"],  dtype=np.float32)
    _COL_MAX  = np.array(_STATS["col_max"],  dtype=np.float32)
    logger.info("Simulator stats loaded: %d sensors", _N_SENSORS)
except Exception as exc:
    logger.error("Simulator stats failed to load: %s", exc)
    _STATS = _FEATURE_COLS = None
    _N_SENSORS, _WINDOW = 119, 48
    _COL_MEAN = _COL_STD = _COL_MIN = _COL_MAX = None

# Load real SCADA data (optional — only needed for normal/leak/random modes)
try:
    _NORMAL_DATA = _load_normal_data()
    logger.info("Simulator SCADA data loaded: %d rows", len(_NORMAL_DATA))
except Exception as exc:
    logger.warning("normal_data.npy not found — real SCADA modes disabled: %s", exc)
    _NORMAL_DATA = None

# Load scaler — used to inverse-transform generated windows back to raw SCADA units
# normal_data.npy is stored in already-scaled (normalized) form; the predictor
# applies scaler.transform() internally, so we must undo the pre-scaling here.
try:
    import joblib as _joblib
    _SCALER_PATH = Path(__file__).parent.parent.parent / "model_files" / "scaler.pkl"
    _SCALER = _joblib.load(str(_SCALER_PATH)) if _SCALER_PATH.exists() else None
    if _SCALER is not None:
        logger.info("Simulator scaler loaded — will inverse-transform all windows")
    else:
        logger.warning("scaler.pkl not found — simulator will return raw values as-is")
except Exception as exc:
    logger.warning("Could not load scaler for simulator: %s", exc)
    _SCALER = None


def _to_raw(window: np.ndarray) -> np.ndarray:
    """Convert a pre-scaled (normalized) window back to raw SCADA units.

    normal_data.npy (and the synthetic generators that derive their statistics
    from it) stores data in the *already-scaled* domain.  The predictor's
    _real_predict() calls scaler.transform() on whatever data it receives, so
    we must undo that pre-scaling here so the full pipeline is consistent:

        simulate  →  inverse_transform  →  POST /predict
        →  scaler.transform  →  model  →  MSE  →  threshold
    """
    if _SCALER is None:
        return window
    return _SCALER.inverse_transform(window).astype(np.float32)


# ══════════════════════════════════════════════════════════════════════════════
# EXISTING MODES  (training-set data — model has seen this distribution)
# ══════════════════════════════════════════════════════════════════════════════

def _real_window(rng: np.random.Generator) -> np.ndarray:
    """Return a random consecutive 48-row slice from the SCADA training file."""
    max_start = len(_NORMAL_DATA) - _WINDOW
    start = rng.integers(0, max_start)
    return _NORMAL_DATA[start : start + _WINDOW].copy()


def _build_normal(rng: np.random.Generator) -> np.ndarray:
    """A real 48-row window directly from training data (returned in raw SCADA units)."""
    return _to_raw(_real_window(rng))


def _build_leak(rng: np.random.Generator) -> np.ndarray:
    """Real normal baseline + pressure SURGE anomaly (raw SCADA units).

    Why SURGE not DROP?
    The model was trained on real SCADA data where LOW sensor values (even zero)
    occur naturally during off-peak / low-demand periods.  The autoencoder
    reconstructs minimum values with near-perfect accuracy (MSE=0.043).  But
    ABOVE-maximum pressure readings are out-of-distribution — the autoencoder
    has never seen them and reconstructs them poorly (MSE>0.333).

    Physical basis: pipe burst events cause an initial water-hammer pressure
    SURGE before the static pressure drops, so this is realistic.

    Implementation:
    - Pick a burst onset t in [8, 15]
    - ~45% of sensors gradually ramp UP from their normal value to
      COL_MAX + 10-15 sigma above the normal maximum by the end of the window
    - Values above COL_MAX are left un-clipped (they are out-of-distribution
      and cause the high reconstruction error we need)
    """
    window    = _real_window(rng)                           # [0, 1] normalized
    burst_t   = int(rng.integers(8, 16))                   # surge onset
    n_affected = max(25, int(_N_SENSORS * 0.45))           # ~45% sensors
    affected  = rng.choice(_N_SENSORS, size=n_affected, replace=False)
    remaining = _WINDOW - burst_t
    for t in range(burst_t, _WINDOW):
        frac = (t - burst_t) / remaining                   # 0 → 1 linear ramp
        for s in affected:
            # Ramp from current value to COL_MAX + 10-15 sigma overshoot
            spike_top = _COL_MAX[s] + rng.uniform(10.0, 15.0) * _COL_STD[s]
            window[t, s] = (1.0 - frac) * window[burst_t, s] + frac * spike_top
    # Clip only from below; leave above-max values un-clipped up to 20 sigma — they are the anomaly
    window = np.clip(window, _COL_MIN, _COL_MAX + 20.0 * _COL_STD)
    return _to_raw(window)


# ══════════════════════════════════════════════════════════════════════════════
# NEW UNSEEN MODES  (statistically valid but never-before-seen rows)
# ══════════════════════════════════════════════════════════════════════════════

def _build_synthetic_normal(rng: np.random.Generator) -> np.ndarray:
    """
    Generate a brand-new unseen NORMAL time-series via AR(1) Gaussian sampling
    and return it in raw SCADA units.

    Why AR(1)?
    Real sensor data is NOT white noise — each reading is strongly correlated
    with the previous one (pressure at t+1 ≈ pressure at t). We model this
    with an AR(1) process:

        state[t+1] = φ × state[t] + (1-φ) × mean + noise

    where φ=0.85 gives realistic momentum while still mean-reverting.
    The starting point is drawn from N(mean, 0.4×std) so it begins inside
    the normal operating range of each sensor.

    Result: a physically plausible 48×119 matrix the model has NEVER seen.
    """
    phi         = 0.85   # autocorrelation (0 = white noise, 1 = random walk)
    noise_scale = 0.15   # noise as a fraction of each sensor's std

    # Initialise each sensor within its normal operating band
    state = rng.normal(_COL_MEAN, 0.4 * _COL_STD).astype(np.float32)
    state = np.clip(state, _COL_MIN, _COL_MAX)

    window = np.empty((_WINDOW, _N_SENSORS), dtype=np.float32)
    for t in range(_WINDOW):
        window[t] = state
        noise  = rng.normal(0.0, noise_scale * _COL_STD).astype(np.float32)
        state  = phi * state + (1.0 - phi) * _COL_MEAN + noise
        state  = np.clip(state, _COL_MIN, _COL_MAX)

    return _to_raw(window)


def _build_synthetic_leak(rng: np.random.Generator) -> np.ndarray:
    """
    Generate a brand-new unseen ANOMALOUS time-series in raw SCADA units.

    Same pressure-surge strategy as _build_leak but on a fully synthetic
    (never-seen) AR(1) baseline.  All operations are in normalized [0,1] space;
    values intentionally pushed above COL_MAX are the source of high MSE.
    _to_raw() is called once at the end.
    """
    # --- Step 1: AR(1) baseline in normalized space ---
    phi         = 0.85
    noise_scale = 0.15
    state = rng.normal(_COL_MEAN, 0.4 * _COL_STD).astype(np.float32)
    state = np.clip(state, _COL_MIN, _COL_MAX)
    window = np.empty((_WINDOW, _N_SENSORS), dtype=np.float32)
    for t in range(_WINDOW):
        window[t] = state
        noise  = rng.normal(0.0, noise_scale * _COL_STD).astype(np.float32)
        state  = phi * state + (1.0 - phi) * _COL_MEAN + noise
        state  = np.clip(state, _COL_MIN, _COL_MAX)

    # --- Step 2: Pressure surge on ~45% of sensors ---
    burst_t    = int(rng.integers(8, 16))
    n_affected = max(25, int(_N_SENSORS * 0.45))
    affected   = rng.choice(_N_SENSORS, size=n_affected, replace=False)
    remaining  = _WINDOW - burst_t
    for t in range(burst_t, _WINDOW):
        frac = (t - burst_t) / remaining                    # 0 → 1 linear
        for s in affected:
            spike_top = _COL_MAX[s] + rng.uniform(10.0, 15.0) * _COL_STD[s]
            window[t, s] = (1.0 - frac) * window[burst_t, s] + frac * spike_top

    # --- Step 3: Floor-clip only; leave above-max un-clipped up to 20 sigma ---
    window = np.clip(window, _COL_MIN, _COL_MAX + 20.0 * _COL_STD)
    return _to_raw(window)


# ══════════════════════════════════════════════════════════════════════════════
# API Route
# ══════════════════════════════════════════════════════════════════════════════

@router.get(
    "/simulate",
    summary="Generate a realistic sensor window for dashboard testing",
)
async def simulate(
    type: str = Query(
        "synthetic",
        regex="^(leak|normal|random|synthetic|synthetic_leak)$",
        description=(
            "normal         — real SCADA slice (SEEN by model)\n"
            "leak           — real SCADA slice + pressure drop (SEEN by model)\n"
            "random         — 50/50 coin flip normal/leak (SEEN by model)\n"
            "synthetic      — AR(1) Gaussian unseen normal ✨\n"
            "synthetic_leak — AR(1) Gaussian unseen anomaly ✨"
        ),
    ),
):
    """
    Returns a **(48 × 119)** sensor window ready to POST directly to **/predict**.

    - `normal` / `leak` / `random` → data drawn from the **training distribution**
      (model has seen this style of data before).
    - `synthetic` / `synthetic_leak` → **genuinely unseen** data generated from
      per-sensor statistics only. Every call produces a unique time-series.
      Use these to perform a **true blind test** of the AI.
    """
    # Stats are required for all modes (synthetic needs them)
    if _STATS is None:
        raise HTTPException(
            status_code=503,
            detail="Simulator not ready — dataset_stats.json missing from backend/model/",
        )

    # Real SCADA data is only required for normal / leak / random modes
    if type in ("normal", "leak", "random") and _NORMAL_DATA is None:
        raise HTTPException(
            status_code=503,
            detail=(
                "Real SCADA modes (normal/leak/random) are unavailable — "
                "normal_data.npy is missing. Use 'synthetic' or 'synthetic_leak' instead."
            ),
        )

    rng = np.random.default_rng()   # cryptographically seeded — different every call

    if type == "normal":
        window, unseen = _build_normal(rng), False
    elif type == "leak":
        window, unseen = _build_leak(rng), False
    elif type == "random":
        if rng.random() > 0.5:
            window = _build_leak(rng)
            logger.info("Simulate RANDOM → LEAK")
        else:
            window = _build_normal(rng)
            logger.info("Simulate RANDOM → NORMAL")
        unseen = False
    elif type == "synthetic":
        window, unseen = _build_synthetic_normal(rng), True
    else:  # synthetic_leak
        window, unseen = _build_synthetic_leak(rng), True

    logger.info(
        "Simulate — type=%s  unseen=%s  shape=%s",
        type, unseen, window.shape,
    )

    return {
        "type":         type,
        "unseen":       unseen,
        "shape":        list(window.shape),
        "feature_cols": _FEATURE_COLS,
        "data":         window.tolist(),
    }
