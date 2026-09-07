# 💧 LeakLens — Water Leakage Detection System

> **AI-powered anomaly detection** for SCADA water networks using a trained Conv1D Autoencoder.  
> Full-stack system: FastAPI backend · Web dashboard · Flutter mobile app.

---

## 🏗️ Architecture

```
Water-Leak/
├── backend/                 ← FastAPI + TensorFlow inference
│   ├── main.py              ← App entry point
│   ├── model/
│   │   ├── predictor.py     ← Real + Mock autoencoder inference
│   │   └── zones.py         ← Zone mapping (n1→Zone1 … n300→Zone5)
│   ├── api/routes/
│   │   ├── predict.py       ← POST /predict
│   │   ├── reports.py       ← POST /report · GET /alerts
│   │   ├── analytics.py     ← GET /analytics · GET /timeseries
│   │   └── auth.py          ← User & Engineer register/login
│   ├── db/
│   │   ├── database.py      ← SQLAlchemy + SQLite engine
│   │   └── models.py        ← users · engineers · reports · anomalies · sensor_logs · outages
│   ├── schemas/
│   │   └── schemas.py       ← Pydantic v2 request/response models
│   ├── model_files/         ← DROP .keras + .pkl FILES HERE
│   ├── requirements.txt
│   └── .env
│
├── dashboard/               ← Browser-based control panel
│   ├── index.html
│   ├── style.css            ← Dark-mode glassmorphism design
│   └── app.js               ← Synthetic data generators + Chart.js
│
├── mobile/                  ← Flutter mobile app
│   ├── pubspec.yaml
│   └── lib/
│       ├── main.dart
│       ├── theme/app_theme.dart
│       ├── models/prediction_model.dart
│       ├── services/api_service.dart
│       └── screens/
│           ├── role_selection_screen.dart
│           ├── auth/login_screen.dart
│           ├── auth/register_screen.dart
│           ├── user/user_home_screen.dart
│           ├── user/report_issue_screen.dart
│           ├── engineer/engineer_dashboard_screen.dart
│           └── engineer/analytics_screen.dart
│
├── run_system.bat        ← One-click Windows startup script
└── another_copy_of_water_leakage_advanced.py  ← Original training notebook
```

---

## 🚀 Quick Start

### 1 · Backend

```bat
# Windows — double-click or run:
run_system.bat
```

```bash
# Docker (Recommended)
docker-compose up --build
```

```bash
# Manual
cd backend
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

| URL | Purpose |
|-----|---------|
| http://localhost:8000/docs | Interactive Swagger UI |
| http://localhost:8000/health | Model status + sensor count |
| http://localhost:8000/redoc | ReDoc documentation |

---

### 2 · Web Dashboard

Simply open in your browser — **no build step needed**:

```
dashboard/index.html
```

Click the three buttons to test the detection pipeline live.

---

### 3 · Mobile App

```bash
cd mobile
flutter pub get
flutter run
```

> **Android emulator:** Backend URL is pre-set to `http://10.0.2.2:8000`  
> **Physical device / iOS:** Update `baseUrl` in `lib/services/api_service.dart`

---

## 🧠 Model Artifacts

Place your trained files in `backend/model_files/`:

```
backend/model_files/
├── water_leakage_model.keras   ← from training notebook
├── scaler.pkl                  ← RobustScaler
└── threshold.pkl               ← 95th-percentile MSE float
```

**No files?** The backend auto-switches to a smart **mock predictor** that correctly classifies Leak / Normal / Random data based on statistical patterns — perfect for development.

---

## 📡 API Reference

### `POST /api/v1/predict`

```json
// Request
{
  "data": [[...], [...], ...]   // shape (48, N_sensors)
}

// Response
{
  "is_anomaly": 1,
  "confidence": 0.8742,
  "mse": 0.234512,
  "threshold": 0.100000,
  "top_sensors": ["n33", "n28", "n74"],
  "zone": "Zone 2",
  "sensor_errors": [0.001, 0.023, ...],
  "message": "⚠️ Leak detected in Zone 2 with 87.4% confidence",
  "latency_ms": 12.4
}
```

### `POST /api/v1/report`
```json
{ "zone": "Zone 3", "description": "Visible puddle near node 65", "severity": "high" }
```

### `GET /api/v1/alerts?limit=50&zone=Zone+2&anomaly_only=true`

### `GET /api/v1/analytics?days=30`

### `GET /api/v1/timeseries?hours=24`

### `POST /api/v1/auth/user/register`
```json
{ "name": "Ahmed", "address": "...", "zone": "Zone 1", "phone": "...", "email": "...", "password": "..." }
```

### `POST /api/v1/auth/engineer/login`
```json
{ "engineer_id": "ENG-001", "password": "..." }
```

### `POST /api/v1/outages`
```json
{ "zone": "Zone 1", "title": "Main pipe repair", "description": "...", "start_time": "2026-05-14T20:00:00Z", "end_time": "2026-05-14T22:00:00Z" }
```

### `GET /api/v1/outages`

---

## 🗄️ Database Schema

| Table | Key Columns |
|-------|-------------|
| `users` | id · name · email · phone · zone · password_hash |
| `engineers` | id · engineer_id · name · password_hash |
| `reports` | id · user_id · zone · description · severity · status |
| `anomalies` | id · is_anomaly · confidence · mse · threshold · top_sensors · zone |
| `sensor_logs` | id · timestamp · num_sensors · mean_value · std_value · anomaly_detected |
| `water_outages` | id · zone · title · description · start_time · end_time · is_cancelled |

---

## 🌐 Zone Mapping

| Zone | Sensors | Description |
|------|---------|-------------|
| Zone 1 | n1 – n30 | Early Network (Intake / Primary Pipes) |
| Zone 2 | n31 – n60 | Middle Distribution Network |
| Zone 3 | n61 – n90 | Main Distribution Grid |
| Zone 4 | n91 – n120 | End Network / High Pressure Zones |
| Zone 5 | n121 – n300 | Extended / Remote Network |

---

## 📱 Mobile App Screens

| Screen | Role | Features |
|--------|------|---------|
| Role Selection | Both | Animated User/Engineer card selection |
| Login | Both | Email/phone + password · Forgot password |
| Register | User | 6-field form · Zone dropdown · Password confirm |
| User Home | User | Alerts feed · Report issue · Water-saving tips · Active Outages |
| Report Issue | User | Zone + severity + description · Success animation |
| Outages | User | Full-screen alarm notification · Countdown timer |
| Engineer Dashboard | Engineer | Overview KPIs · Pressure/flow charts · Alerts tab |
| Analytics | Engineer | Bar chart · Zone leaks table · Period filter |

---

## 🔒 Security Notes

- Passwords hashed with `bcrypt` (12 rounds)
- JWT tokens with 7-day expiry
- Change `SECRET_KEY` in `.env` before any production deployment
- Restrict CORS `allow_origins` to your actual frontend domain in production

---

## 🧪 Testing the Prediction Pipeline

```bash
# Leak data — should return is_anomaly: 1
curl -X POST http://localhost:8000/api/v1/predict \
  -H "Content-Type: application/json" \
  -d @- << 'EOF'
{
  "data": [
    [-0.0, -0.1, -0.2, 0.01, 0.02, 0.0, -0.01, 0.01, 0.0, -0.02,
      0.0, 0.01, -0.01, 0.0, 0.01, -0.01, 0.0, 0.01, 0.0, -0.01],
    [-0.1, -0.2, -0.35, 0.0, 0.01, -0.01, 0.0, 0.01, 0.0, -0.01,
      0.01, 0.0, -0.01, 0.0, 0.01, 0.0, 0.01, 0.0, 0.01, 0.0]
  ]
}
EOF
```

> **Tip:** Use the web dashboard buttons for a richer visual test experience.
