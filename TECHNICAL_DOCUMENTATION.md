# LeakLens — Full Technical Documentation

> **Version:** 1.0.0 | **Platform:** Android (Primary), iOS (Secondary)
> **Architecture:** Flutter Mobile + FastAPI Backend + Vanilla JS Dashboard + Firebase Cloud Messaging

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Mobile Application — Flutter](#mobile-application--flutter)
3. [Backend API — Python / FastAPI](#backend-api--python--fastapi)
4. [Web Dashboard](#web-dashboard)
5. [Database Architecture](#database-architecture)
6. [API Endpoints Reference](#api-endpoints-reference)
7. [Android Permissions & Manifest](#android-permissions--manifest)
8. [Firebase Integration](#firebase-integration)
9. [ML Model — Conv1D Autoencoder](#ml-model--conv1d-autoencoder)
10. [Data Flow Diagrams](#data-flow-diagrams)
11. [Security Architecture](#security-architecture)
12. [Deployment Guide](#deployment-guide)

---

## System Overview

LeakLens is an AI-powered water leakage detection platform composed of three tightly integrated components:

| Component | Technology | Role |
|---|---|---|
| Mobile App | Flutter / Dart | End-user interface (users & engineers) |
| Backend API | Python / FastAPI + SQLite | Data processing, ML inference, auth, FCM |
| Web Dashboard | Vanilla HTML/CSS/JS | SCADA simulation & engineer control panel |
| Push Service | Firebase Cloud Messaging (FCM) | Real-time alerts to mobile devices |
| ML Engine | TensorFlow / Keras Conv1D Autoencoder | Anomaly detection from sensor windows |

---

## Mobile Application — Flutter

### Framework & SDK

- **Flutter SDK** `>=3.3.0 <4.0.0` — Google's open-source UI toolkit that compiles to native ARM code. Uses a single Dart codebase to target both Android and iOS. Flutter renders its own widgets using the Skia/Impeller GPU engine rather than using platform widgets, giving pixel-perfect UI control.
- **Dart Language** — Strongly typed, AOT-compiled language. All application logic, state management, and UI is written in Dart.
- **Material Design 3** — `uses-material-design: true` in `pubspec.yaml` enables access to all Material widgets (Scaffold, AppBar, ElevatedButton, etc.) used as base building blocks.

### App Entry Point — `main.dart`

`main.dart` bootstraps the entire application. Key responsibilities:
- Initializes Firebase (`Firebase.initializeApp()`)
- Initializes timezone data (`tz.initializeTimeZones()`)
- Initializes the Alarm package (`Alarm.init()`)
- Creates the `water_leak_alerts` Android notification channel at max importance
- Registers `onDidReceiveNotificationResponse` for notification tap handling
- Checks `getNotificationAppLaunchDetails()` for cold-start notification taps
- Reads `SharedPreferences` for `access_token` and `role` to determine the initial route
- Exposes `GlobalKey<NavigatorState> navigatorKey` and `VoidCallback? onNotificationTapShowAlarm` for cross-widget alarm triggering
- Sets portrait-only orientation lock
- Wires `MaterialApp` with named routes: `/role`, `/user-home`, `/engineer`

### Application Architecture

The app follows a **service-oriented architecture** with:
- `lib/services/api_service.dart` — Single HTTP client class encapsulating all REST calls
- `lib/models/prediction_model.dart` — All Dart data models with `fromJson` parsers
- `lib/screens/` — Screen-level widgets organized by role (`user/`, `engineer/`, `auth/`)
- `lib/theme/app_theme.dart` — Centralized design token system (colors, radii, shadows)
- `lib/utils/nav.dart` — Navigation helpers (e.g., `pushFade` for custom page transitions)

### Networking Libraries

#### `http` (^1.2.1)
- Package: `package:http/http.dart`
- Used in `ApiService` for all HTTP communication.
- All requests have a 15-second GET timeout and 30-second POST timeout.
- Requests include `Content-Type: application/json` and `Accept: application/json` headers.
- The `_parse()` helper method automatically throws an `ApiException` for any response with HTTP status >= 400.

#### `dio` (^5.4.3+1)
- Included as a dependency for advanced use cases requiring interceptors, multipart form data uploads, or request cancellation tokens.

### State Management

#### `provider` (^6.1.2)
- Used as the dependency injection and reactive state layer.
- Wraps `InheritedWidget` to propagate state changes through the widget tree without tight coupling.

### User Interface Libraries

#### `google_fonts` (^6.2.1)
- Loads the **Inter** typeface at runtime from Google's font CDN.
- Used in virtually every `Text` widget: `GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)`
- Inter was chosen for its legibility at small sizes and its modern, professional appearance.

#### `animate_do` (^3.3.4)
- Provides declarative animation wrappers that don't require `AnimationController` boilerplate.
- Used animations: `FadeInUp`, `FadeInLeft`, `FadeIn`, `ZoomIn`
- Each card/section on the home screen uses a staggered `delay` to create cascading entrance animations.
- Example: `FadeInUp(delay: Duration(milliseconds: 200), child: SectionTitle('Recent Alerts'))`

#### `fl_chart` (^0.68.0)
- Renders interactive, animated charts.
- Used in the Engineer Analytics screen for:
  - **BarChart** — Zone-wise leak frequency visualization
  - **LineChart** — Live 24-hour timeseries (pressure & flow)
- Charts support touch callbacks, tooltips, and custom axis labels.

#### `flutter_svg` (^2.0.10+1)
- Renders SVG assets (icons, illustrations) at any resolution without pixelation.
- Used for zone map illustrations and decorative UI elements.

#### `cached_network_image` (^3.3.1)
- Automatically caches network images to disk and memory.
- Used wherever user profile pictures or remote images are displayed.

### Notifications & Alarm Libraries

#### `firebase_core` (^4.7.0)
- Mandatory base package that initializes the Firebase platform plugin.
- Must be called before any other Firebase service: `await Firebase.initializeApp()`

#### `firebase_messaging` (^16.2.0)
- Implements Firebase Cloud Messaging (FCM) client.
- **Foreground messages:** `FirebaseMessaging.onMessage.listen()` — fires `_showNotification()` to display a local notification while the app is open.
- **Background messages:** `@pragma('vm:entry-point') _firebaseMessagingBackgroundHandler()` — top-level function that runs in an isolate when the app is in background/killed.
- **Topic subscriptions:** Users subscribe to their zone's FCM topic (e.g., `Zone_1`) so broadcast alerts are targeted by zone.
- **Notification tap (background):** `FirebaseMessaging.onMessageOpenedApp` fires when the user taps an FCM notification while the app is backgrounded.

#### `flutter_local_notifications` (^17.1.2)
- Displays system-level notifications programmatically.
- Notification channel ID: `water_leak_alerts` (matches `AndroidManifest.xml` meta-data).
- Channel importance: `Importance.max` (heads-up notifications, sound, vibration).
- Key functions implemented:
  - `showLocalNotification(title, body, {isAlarm})` — shows an immediate notification. When `isAlarm=true`, sets `fullScreenIntent: true`, `category: alarm`, `audioAttributesUsage: alarm`.
  - `scheduleAlarmNotification(id, title, body, scheduledTime)` — uses `zonedSchedule()` with `AndroidScheduleMode.exactAllowWhileIdle` to fire at a precise future time, even in Doze mode.
- **Tap handling:** `onDidReceiveNotificationResponse` callback triggers `_handleNotificationTap()` → calls `onNotificationTapShowAlarm()` callback → `UserHomeScreen._checkRingingAlarms()`.
- **Background tap:** Top-level `@pragma('vm:entry-point') _onBackgroundNotificationTap()` stores payload in `_pendingNotificationPayload`.
- **Cold-start tap:** `getNotificationAppLaunchDetails()` checked in `main()` to detect if app was opened by a notification tap.

#### `alarm` (^5.1.5)
- Specialized package for scheduling persistent outage alarms that survive app termination.
- Internally registers an Android foreground service and uses `AlarmManager.setExactAndAllowWhileIdle()`.
- Key `AlarmSettings` fields used:
  - `id` — outage database ID (used to stop the correct alarm)
  - `dateTime` — exact UTC time of outage start
  - `assetAudioPath` — `'assets/audio/alarm.mp3'` (bundled alarm sound)
  - `loopAudio: true` — repeats sound until dismissed
  - `vibrate: true`
  - `androidFullScreenIntent: true` — triggers the red full-screen alarm UI
  - `androidStopAlarmOnTermination: false` — alarm persists even after process kill
- Alarm lifecycle:
  1. `Alarm.set(alarmSettings)` — registers future alarm
  2. `Alarm.ringStream.stream` — StreamSubscription that fires `_handleAlarmRing()` when alarm triggers while app is running
  3. `Alarm.isRinging(id)` — checked on app resume/init to detect missed alarms
  4. `Alarm.stop(id)` — called when user taps "STOP ALARM"

#### `workmanager` (^0.9.0)
- Schedules background tasks using Android's WorkManager API.
- Ensures tasks run even with battery optimization restrictions.

### Utilities & Storage Libraries

#### `shared_preferences` (^2.3.1)
- Persistent key-value store backed by Android `SharedPreferences` / iOS `NSUserDefaults`.
- Keys stored:
  - `access_token` — JWT bearer token
  - `role` — `"user"` or `"engineer"`
  - `custom_base_url` — user-configured backend URL
  - `dismissed_alerts` — List of alert IDs the user has dismissed (prevents re-showing)

#### `intl` (^0.19.0)
- Internationalization and date/time formatting.
- Used for outage time display: `DateFormat('h:mm a').format(localTime)` → `"1:05 PM"`
- Converts UTC timestamps from API to device local timezone before formatting.

#### `permission_handler` (^11.3.1)
- Cross-platform permission management.
- Permissions requested by the app:
  - `Permission.notification` — required for FCM and local notifications (Android 13+)
  - `Permission.scheduleExactAlarm` — required for `AlarmManager` exact scheduling (Android 12+)
  - `Permission.systemAlertWindow` — allows overlay windows for alarm screen
- Provides `openAppSettings()` to redirect users to system settings when permissions are permanently denied.

### User Roles & Screens

#### Regular User (`role = "user"`)
- **`login_screen.dart`** — Email/phone + password login with `POST /api/v1/auth/user/login`
- **`user_home_screen.dart`** — Main dashboard showing recent alerts (filtered by zone), quick action buttons, water outage badge counter, water saving tips. Implements `WidgetsBindingObserver` to check for ringing alarms on app resume.
- **`outages_screen.dart`** — Displays upcoming water outages for the user's zone with 12-hour AM/PM time formatting. Allows setting an alarm for each outage.
- **`report_issue_screen.dart`** — Form to submit a manual water issue report with zone, description, and severity fields.

#### Engineer (`role = "engineer"`)
- **`engineer_dashboard_screen.dart`** — Tabbed interface with:
  - **Alerts Tab** — Live feed of model-detected anomalies AND broadcast alerts. Broadcast alerts show 📢 orange styling with custom message; model alerts show 🚨 red with sensor/confidence details.
  - **Reports Tab** — User-submitted reports showing reporter's real name (via `user_name` field), zone, severity badge, description, and status update controls (pending → investigating → resolved).
  - **Analytics Tab** — Chart-based zone analysis.
  - **Outages Tab** — Engineer creates/deletes outage schedules for any zone.
- **`analytics_screen.dart`** — Detailed analytics view with bar/line charts.

### Data Models — `prediction_model.dart`

All API responses are deserialized into typed Dart models:

| Model | Purpose | Key Fields |
|---|---|---|
| `PredictionResult` | `/predict` response | `isAnomaly`, `confidence`, `mse`, `threshold`, `topSensors`, `zone`, `sensorErrors` |
| `AlertModel` | `/alerts` response | `id`, `isAnomaly`, `confidence`, `mse`, `topSensors`, `zone`, `message`, `detectedAt`, `source` |
| `ReportModel` | `/reports` response | `id`, `zone`, `description`, `severity`, `status`, `userId`, `userName`, `createdAt` |
| `OutageModel` | `/outages` response | `id`, `zone`, `title`, `description`, `startTime`, `endTime`, `isCancelled` |
| `AnalyticsData` | `/analytics` response | `totalAnomalies`, `totalReports`, `leaksPerZone`, `mostAffectedZone`, `avgConfidence` |
| `TimeseriesPoint` | `/timeseries` response | `timestamp`, `pressure`, `flow`, `isAnomaly`, `zone` |

---

## Backend API — Python / FastAPI

### Framework & Server

#### FastAPI (0.111.0)
The core web framework. FastAPI is chosen for:
- **Performance** — Built on Starlette (ASGI), rivals NodeJS in throughput for async workloads
- **Auto-documentation** — Swagger UI auto-generated at /docs, ReDoc at /redoc
- **Type safety** — Pydantic integration means request/response validation happens automatically
- **Dependency injection** — Depends(get_db) cleanly injects database sessions into route handlers
- **Lifespan events** — @asynccontextmanager async def lifespan(app) runs startup tasks (DB creation, Firebase init, model warm-up, default engineer seed)

#### Uvicorn (0.29.0)
ASGI web server. Run command: uvicorn main:app --reload --host 0.0.0.0 --port 8000
- [standard] extra installs uvloop (high-speed event loop) and httptools (fast HTTP parser)
- --host 0.0.0.0 exposes the API on all network interfaces (required for physical device testing)

### Middleware

Two middleware layers are applied in main.py:

1. **CORSMiddleware** (astapi.middleware.cors) — Allows requests from any origin (llow_origins=["*"]). Permits all HTTP methods and headers. Required so the web dashboard (served from a different origin) can call the API.

2. **Request Timing Middleware** — Custom @app.middleware("http") decorator measures every request using 	ime.perf_counter() and injects the result as X-Process-Time-Ms in the response header for performance monitoring.

### Global Error Handler
@app.exception_handler(Exception) catches any unhandled exception, logs it with full traceback, and returns a clean JSON {"detail": "Internal server error"} with HTTP 500, preventing raw Python tracebacks from leaking to clients.

### API Routes (all under prefix /api/v1)

| Router File | Tag | Key Endpoints |
|---|---|---|
| predict.py | 🔍 Prediction | POST /predict |
| 
eports.py | 📢 Reports & Alerts | POST /report, GET /alerts, GET /reports, POST /broadcast, GET /latest, PATCH /reports/{id}/status, DELETE /alerts/{id}, DELETE /reports/{id}, POST /reset-data |
| nalytics.py | 📊 Analytics | GET /analytics, GET /timeseries |
| uth.py | 🔐 Authentication | POST /auth/user/register, POST /auth/user/login, POST /auth/engineer/register, POST /auth/engineer/login |
| simulate.py | 🧪 Simulator | POST /simulate |
| outages.py | 📅 Water Outages | POST /outages, GET /outages, DELETE /outages/{id} |

### Database Libraries

#### SQLAlchemy (2.0.30)
ORM used for all database interactions. Tables are defined as Python classes:
- User — users table: id, 
ame, ddress, zone, phone, email, password_hash, is_active, created_at; has one-to-many relationship with Report
- Engineer — engineers table: id, engineer_id (e.g., ENG-001), 
ame, password_hash, is_active, created_at
- Report — 
eports table: id, user_id (FK→users), zone, description, status (pending/investigating/resolved), severity (low/medium/high), created_at, updated_at; exposes computed user_name property via relationship
- Anomaly — nomalies table: id, is_anomaly, confidence, mse, 	hreshold, 	op_sensors (JSON), zone, sensor_errors (JSON), source (model/manual), message (TEXT, nullable), detected_at
- SensorLog — sensor_logs table: id, 	imestamp, 
um_sensors, mean_value, std_value, nomaly_detected, zone, logged_at
- WaterOutage — water_outages table: id, zone, 	itle, description, start_time, end_time, created_at, is_cancelled

Schema creation: Base.metadata.create_all(bind=engine) on startup. Dynamic migration (ALTER TABLE) for the message column executed with a try/except to be non-destructive.

#### aiosqlite (0.20.0)
Provides async SQLite driver so database I/O doesn't block the async event loop.
Database file: water_leak.db (SQLite binary, stored locally in the backend directory).

### Authentication & Security

#### passlib[bcrypt] (1.7.4) + bcrypt (4.0.1)
- Password hashing: passlib.context.CryptContext(schemes=["bcrypt"]) 
- Hashing: pwd_context.hash(plain_password)
- Verification: pwd_context.verify(plain, hashed)
- bcrypt automatically salts hashes, making rainbow-table attacks infeasible

#### python-jose[cryptography] (3.3.0)
- JWT signing: jose.jwt.encode(payload, SECRET_KEY, algorithm="HS256")
- JWT decoding: jose.jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
- Token payload contains: sub (user/engineer ID), 
ole, exp (expiry)
- Token returned on successful login: {"access_token": "...", "token_type": "bearer", "role": "user", "user_id": 1, "name": "Ahmed", "zone": "Zone 1"}
- Stored in mobile SharedPreferences and sent as Authorization: Bearer <token> header on protected requests

### Data Validation — Pydantic (2.7.1)

All request bodies and response models are Pydantic BaseModel subclasses:
- PredictRequest — validates the data array is exactly 48 timesteps with consistent sensor count using a @field_validator
- ReportCreate — enforces description is 5-1000 characters, zone is non-empty
- BroadcastRequest — zone, message, optional severity
- OutageCreate — validates end_time > start_time
- AlertResponse — uses @field_serializer to always output detected_at in ISO 8601 UTC format with Z suffix for correct mobile parsing
- OutageResponse — uses @field_serializer to always format start_time/end_time with UTC Z suffix
- All response models have model_config = {"from_attributes": True} (Pydantic v2 ORM mode)

### Machine Learning Stack

#### TensorFlow (2.16.1) / Keras 3
The trained Conv1D Autoencoder is loaded at startup:
- Model path: ackend/model_files/water_leakage_model.keras
- Fallback: conv1d_model.h5 (legacy Keras format)
- os.environ.setdefault("KERAS_BACKEND", "tensorflow") — sets TF as Keras 3 backend
- keras.saving.load_model() — Keras 3 model loading API

#### Model Architecture
- **Type**: Convolutional Autoencoder (encoder-decoder)
- **Input shape**: (1, 48, N_sensors) — batch of 1 window of 48 timesteps × N sensor readings
- **Training task**: Reconstruction (learns to reproduce normal sensor patterns)
- **Anomaly detection**: High reconstruction error (MSE) = unusual = potential leak
- **Threshold**: 95th-percentile MSE from training data =  .3013341724872589 (loaded from 	hreshold.pkl)

#### scikit-learn (1.4.2)
- Loads scaler.pkl — a StandardScaler fitted on training data
- Applied before inference: data_scaled = scaler.transform(data) — zero-mean, unit-variance normalization
- scaler.n_features_in_ tells the predictor how many sensors the model expects

#### joblib (1.4.2)
- Fast serialization/deserialization of Python objects
- joblib.load("scaler.pkl") — loads the sklearn scaler
- joblib.load("threshold.pkl") — loads the float threshold value

#### numpy (1.26.4)
- All tensor math: 
p.mean(), 
p.std(), 
p.argsort()
- MSE computation: sensor_errors = np.mean((data_scaled - reconstruction[0])**2, axis=0)
- Top anomalous sensors: 	op_idx = np.argsort(sensor_errors)[-3:][::-1]

#### Mock Predictor (fallback)
When model files are missing, WaterLeakPredictor._mock_predict() runs:
- Detects pressure drops: rac_dropping = np.mean(time_trend < -0.3)
- Returns deterministic MSE (no randomness) so dashboard tests are consistent
- MSE=0.35 for leak data, MSE=0.05 for normal data, MSE=0.30 or 0.08 for random

### Third-Party Integrations

#### firebase-admin (6.5.0)
Used on the server side to send push notifications:
- Initialized with service account: credentials.Certificate("firebase-adminsdk.json")
- **Topic-based messaging** — no need to store device tokens; users subscribe to zone-1, zone-2, etc.
- Broadcast message structure:
`python
messaging.Message(
    notification=Notification(title="📢 LeakLens Alert — Zone 1", body="Leak detected!"),
    data={"zone": "Zone 1", "message": "...", "severity": "high", "type": "broadcast_alert"},
    topic="Zone_1"
)
`
- Automatic leak alerts also sent via topic when model detects anomaly from POST /predict

---

## Web Dashboard

### Architecture
Single-page application (SPA) with zero build step — three files:
- index.html — Structure and layout (322 lines)
- style.css — All styling (glassmorphism dark theme, CSS variables, animations)
- pp.js — All logic (data generation, API calls, chart rendering)

### Styling System — CSS Variables
`css
--bg-primary: #0d1b2a        /* deep navy background */
--bg-secondary: #112233      /* card backgrounds */
--cyan: #00d4ff              /* primary accent */
--red: #ff4756               /* anomaly/danger color */
--orange: #ff9100            /* warning color */
--green: #00e676             /* safe/normal color */
--text-primary: #e8f4f8      /* main text */
--text-secondary: #8ab4c8    /* secondary text */
--border: rgba(255,255,255,0.08)  /* subtle borders */
`

### External Libraries (CDN)

#### Chart.js (v4.4.3)
- https://cdn.jsdelivr.net/npm/chart.js@4.4.3/dist/chart.umd.min.js
- **Bar chart** — Per-sensor MSE reconstruction error. Each sensor gets a colored bar: red (top 3 sensors), orange (above threshold), blue (normal). Click shows sensor index and error value.
- **Line chart** — Live 24-hour timeseries. Two datasets: pressure (solid blue) and flow rate (dashed green). Uses 	ype: 'line' with 	ension: 0.4 for smooth curves.

#### chartjs-plugin-annotation (v3.0.1)
- https://cdn.jsdelivr.net/npm/chartjs-plugin-annotation@3.0.1/dist/chartjs-plugin-annotation.min.js
- Draws a horizontal red dashed line at the anomaly threshold value across the MSE chart.
- Annotation config: {type: 'line', yMin: threshold, yMax: threshold, borderColor: 'rgba(255,71,86,0.8)', borderWidth: 2, borderDash: [6,3]}

### JavaScript Functions (app.js)

#### Data Generation
- generateData('leak') — Creates a 48×119 matrix with gradual pressure drops in the first ~20 sensors (simulates a real SCADA leak signature)
- generateData('normal') — Creates a 48×119 matrix with small random variance around 0 (healthy network)
- generateData('random') — Creates a 48×119 matrix with large random noise (50/50 anomaly expectation)
- generateData('synthetic') — AI-generated unseen healthy data (not in training set)
- generateData('synthetic_leak') — AI-generated unseen anomaly data

#### API Communication
- sendData(type) — Calls POST /api/v1/predict with the generated data matrix. Updates all UI metrics on response.
- sendBroadcast() — Reads #broadcastZone and #broadcastMsg inputs, calls POST /api/v1/broadcast. Shows success/error toast.
- 
egisterEngineer() — Calls POST /api/v1/auth/engineer/register from the modal form.
- checkConnection() — Polls GET /health every 10 seconds. Updates the connection status dot (green=online, red=offline).

#### UI Updates
- updateChart(sensorErrors, topSensors, threshold) — Destroys and re-renders the Chart.js bar chart on every prediction
- updateStatus(result) — Animates the status card between idle/anomaly/normal states with appropriate colors and emojis
- logRequest(type, result) — Appends a timestamped entry to the scrollable request log panel

---

## Database Architecture

### Engine & File
- **SQLite** — single-file relational database (water_leak.db)
- **Async driver**: iosqlite for non-blocking I/O
- **Connection URL**: sqlite+aiosqlite:///./water_leak.db
- **Session factory**: SessionLocal = sessionmaker(bind=engine)
- **Dependency injection**: def get_db(): db = SessionLocal(); try: yield db; finally: db.close()

### Table Relationships
`
users ──┐
        ├─< reports (user_id FK, nullable)
        │
engineers
        
anomalies (standalone — created by model predictions and manual broadcasts)
sensor_logs (standalone — logs each prediction window's stats)
water_outages (standalone — created by engineers, consumed by mobile app)
`

### Schema Migration Strategy
No Alembic is used. Instead, a safe startup migration pattern:
1. Base.metadata.create_all() creates all missing tables on every startup (idempotent)
2. For new columns on existing tables: ALTER TABLE anomalies ADD COLUMN message TEXT executed inside 	ry/except — succeeds on first run, silently ignored on subsequent starts

---

## API Endpoints Reference

### Health
| Method | Path | Description |
|---|---|---|
| GET | /health | Returns model status, sensor count, threshold, version |
| GET | / | Welcome message + docs link |

### Prediction
| Method | Path | Body | Returns |
|---|---|---|---|
| POST | /api/v1/predict | {data: [[float]], forced_zone?: str} | {is_anomaly, confidence, mse, threshold, top_sensors, zone, sensor_errors, message} |

### Reports & Alerts
| Method | Path | Query Params | Description |
|---|---|---|---|
| POST | /api/v1/report | — | Submit user report |
| GET | /api/v1/alerts | limit, zone, nomaly_only | Get model/broadcast alerts |
| GET | /api/v1/reports | limit, zone, status | Get user reports (engineer view) |
| PATCH | /api/v1/reports/{id}/status | 
ew_status | Update report status |
| GET | /api/v1/latest | zone, since | Latest alert since timestamp |
| POST | /api/v1/broadcast | {zone, message, severity} | Send broadcast + FCM push |
| DELETE | /api/v1/alerts/{id} | — | Delete alert record |
| DELETE | /api/v1/reports/{id} | — | Delete report record |
| POST | /api/v1/reset-data | — | Wipe all operational data |

### Analytics
| Method | Path | Query Params | Description |
|---|---|---|---|
| GET | /api/v1/analytics | days (1-365) | Zone leak/report counts, most affected zone, avg confidence |
| GET | /api/v1/timeseries | hours (1-168), zone | Pressure/flow timeseries with anomaly labels |

### Authentication
| Method | Path | Body | Returns |
|---|---|---|---|
| POST | /api/v1/auth/user/register | {name, address, zone, phone, email, password} | TokenResponse |
| POST | /api/v1/auth/user/login | {email?, phone?, password} | TokenResponse |
| POST | /api/v1/auth/engineer/register | {name, engineer_id, password} | TokenResponse |
| POST | /api/v1/auth/engineer/login | {engineer_id, password} | TokenResponse |

### Water Outages
| Method | Path | Body/Params | Description |
|---|---|---|---|
| POST | /api/v1/outages | {zone, title, description?, start_time, end_time} | Create outage schedule |
| GET | /api/v1/outages | zone?, include_past | Get upcoming outages |
| DELETE | /api/v1/outages/{id} | — | Cancel/delete outage |

---

## Android Permissions & Manifest

### Permissions Declared
| Permission | Purpose |
|---|---|
| INTERNET | HTTP calls to the backend API |
| RECEIVE_BOOT_COMPLETED | Re-register alarms after device restart |
| WAKE_LOCK | Keep CPU alive during alarm processing |
| VIBRATE | Haptic feedback for alerts and alarms |
| POST_NOTIFICATIONS | Required on Android 13+ for any notifications |
| USE_FULL_SCREEN_INTENT | Show the red alarm screen over the lock screen |
| SCHEDULE_EXACT_ALARM | Set precise outage alarms (Android 12+) |
| USE_EXACT_ALARM | Alternative exact alarm permission for Android 13+ |
| FOREGROUND_SERVICE | Keep alarm service running in background |
| SYSTEM_ALERT_WINDOW | Draw the alarm overlay window |

### Activity Configuration
- launchMode="singleTop" — prevents multiple instances when tapping notifications
- showWhenLocked="true" — alarm screen appears even over the Android lock screen
- 	urnScreenOn="true" — wakes the display when an alarm fires
- 	askAffinity="" — ensures proper back-stack behavior when launched from notifications

---

## Firebase Integration

### Architecture
`
Backend (Python) → firebase-admin SDK → FCM Server → Device (Flutter) → firebase_messaging
`

### Topic-Based Push Model
Users are subscribed to zone-specific FCM topics on login:
- Zone_1, Zone_2, Zone_3, Zone_4, Zone_5
- When the model detects a leak in Zone 2, the backend sends to topic Zone_2 — only Zone 2 users receive the alert
- This avoids storing and managing individual device tokens

### Notification Data Payload
Every FCM message has two parts:
1. 
otification — shown by Android as a system notification (title + body)
2. data — key-value map processed by the Flutter app:
   - "type": "broadcast_alert" or "type": "leak_detected" — determines how the app handles it
   - "zone" — which zone
   - "message" — custom text for broadcast alerts

### Firebase Admin SDK Setup
- Service account key: ackend/firebase-adminsdk.json (must NOT be committed to version control)
- Initialization happens in the lifespan startup hook
- Non-fatal: if Firebase fails to initialize, the backend still runs (FCM push becomes unavailable but all other features work)

---

## ML Model — Conv1D Autoencoder

### What is an Autoencoder?
An autoencoder is a neural network that learns to compress input data into a smaller representation (encode), then reconstruct the original input (decode). When trained only on **normal** data, it learns the patterns of normal operation. Anomalous data (leaks) produces high reconstruction error because the model has never seen those patterns.

### Why Conv1D?
1D Convolutions are ideal for time-series data. The Conv1D layers learn local temporal patterns (e.g., a gradual pressure drop over 5-10 consecutive timesteps) that dense layers would miss.

### Input Format
- Shape: (48, N_sensors) — 48 timesteps, N sensor readings per step
- Each row is one second/minute of SCADA readings from the water network
- N sensors ≈ 119 (determined by the scaler at load time)
- Normalization: StandardScaler (zero-mean, unit-variance) applied before inference

### Inference Pipeline
`
Raw SCADA data (48, 119)
        ↓
StandardScaler.transform()  →  data_scaled (48, 119)
        ↓
model.predict([data_scaled])  →  reconstruction (48, 119)
        ↓
diff = data_scaled - reconstruction
sensor_errors = mean(diff², axis=0)  →  per-sensor MSE (119,)
mse = mean(sensor_errors)  →  scalar
        ↓
mse > threshold (0.3013)?  →  is_anomaly = 1
        ↓
top 3 sensors by error → top_sensors → zone mapping
`

### Zone Detection
model/zones.py contains a mapping from sensor IDs to network zones. The dominant_zone() function takes the top anomalous sensors and returns the zone most frequently represented.

### Confidence Calculation
- If anomaly: confidence = min(1.0, 0.5 + (mse - threshold) / (threshold * 2))
- If normal: confidence = max(0.0, 1.0 - mse / threshold)

---

## Security Architecture

### Authentication Flow
`
Client → POST /auth/login {credentials}
Backend → verify password with bcrypt
Backend → sign JWT with HS256 + SECRET_KEY
Backend → return {access_token, role, user_id, name, zone}
Client → store in SharedPreferences
Client → send as "Authorization: Bearer <token>" on protected routes
`

### Password Security
- Passwords are never stored in plain text
- bcrypt automatically generates a unique salt per password
- Work factor makes brute-force attacks computationally expensive

### Sensitive Files (must not be committed)
- ackend/.env — contains SECRET_KEY, database URL, etc.
- ackend/firebase-adminsdk.json — Firebase service account with push notification privileges

---

## Deployment Guide

### Prerequisites
- Python 3.10+
- Flutter SDK 3.3+
- Android Studio / physical Android device
- Firebase project with FCM enabled

### Backend Setup
`ash
cd backend
python -m venv venv
venv\Scripts\activate          # Windows
pip install -r requirements.txt
cp .env.example .env           # fill in SECRET_KEY and other values
uvicorn main:app --host 0.0.0.0 --port 8000
`

### Mobile App Setup
`ash
cd mobile
flutter pub get
# Set backend URL in ApiService._defaultBase or via app settings
flutter run
`

### Dashboard Setup
Open dashboard/index.html in any browser. Set the backend URL in the input field. No build step required.

### Start Everything (Windows)
`at
run_system.bat   # activates venv and starts uvicorn on port 8000
`

### Default Engineer Credentials
On first run, a default engineer is seeded automatically:
- Engineer ID: ENG-001
- Password: dmin123

---

*Documentation generated for LeakLens v1.0.0 — May 2026*
