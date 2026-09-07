# LeakLens — End-to-End System Workflow & Explanation

This document explains **how** the entire LeakLens platform functions, from the moment synthetic data is generated on the dashboard to the second a full-screen alarm rings on a user's mobile device.

---

## 1. Data Generation & Simulation Workflow

Because LeakLens is designed to detect leaks in a physical water distribution network, we need SCADA sensor data. Since we don't have physical pipes hooked up to the demo, the backend provides a sophisticated simulation engine (`/api/v1/simulate`) to generate realistic 48-timestep windows across 119 sensors.

### How the Dashboard Generates Data
The web dashboard doesn't generate the data itself; it acts as a controller. When you click a button on the Control Panel (e.g., "Send Leak Data"):
1. The dashboard makes a `GET` request to `backend/api/v1/simulate?type=leak`.
2. The backend responds with a `(48, 119)` matrix of float values.
3. The dashboard immediately takes that matrix and `POST`s it to `backend/api/v1/predict`.

### The Five Simulation Modes (Backend Logic)
The simulator (`simulate.py`) operates in two distinct tiers to prove the AI isn't just memorizing data:

**Tier 1: Real SCADA Data (The Model has seen this distribution)**
*   `normal`: The backend randomly slices a 48-row window from `normal_data.npy` (the exact dataset the model was trained on).
*   `leak`: It takes a normal slice, picks ~30% of the sensors, and applies a **gradual pressure drop** scaled by each sensor's Interquartile Range (IQR). This mimics a real leak signature mathematically.
*   `random`: A 50/50 coin flip between `normal` and `leak`.

**Tier 2: Blind Tests / Unseen Data (The Model has NEVER seen this)**
*   `synthetic`: The backend generates a brand-new, unseen normal time-series using an **AR(1) Gaussian process** (`state[t+1] = φ × state[t] + (1-φ) × mean + noise`). This creates realistic, mean-reverting sensor fluctuations based purely on the statistical limits of the network, but it guarantees the exact numbers have never been seen by the AI.
*   `synthetic_leak`: The backend generates an unseen normal baseline, picks a random "burst point" (e.g., timestep 15), and applies an **exponentially accelerating pressure drop** (`((t - burst) / remaining) ** 1.5`) to mimic real pipe-burst physics.

---

## 2. The Prediction Pipeline (The "Brain")

Once the dashboard sends the `(48, 119)` matrix to `/api/v1/predict`, the backend's Machine Learning engine (`predictor.py`) takes over.

### Step 1: Preprocessing & Scaling
The model expects data to be standardized. The backend loads a `StandardScaler` (`scaler.pkl`) via `joblib` and transforms the incoming data so that it has zero-mean and unit-variance.

### Step 2: Autoencoder Inference
The scaled data is passed into the **Conv1D Autoencoder** (`water_leakage_model.keras`).
*   The autoencoder compresses the 48 timesteps into a small bottleneck vector (encoding).
*   It then attempts to decompress it back into the original 48 timesteps (decoding).
*   *Crucial Concept:* Because the autoencoder was only trained on healthy, normal water flow, it is excellent at reconstructing normal data, but terrible at reconstructing leak data.

### Step 3: Anomaly Scoring & Thresholding
The backend calculates the **Mean Squared Error (MSE)** between the original input and the autoencoder's reconstruction.
*   It compares this MSE against a pre-calculated 95th-percentile threshold (`0.30133...`).
*   If `MSE > Threshold` → It's a leak (`is_anomaly = True`).
*   If `MSE ≤ Threshold` → The system is healthy (`is_anomaly = False`).

### Step 4: Localization (Finding the Zone)
If a leak is detected, the backend calculates the individual reconstruction error for each of the 119 sensors. 
*   It sorts the sensors by error: `np.argsort(sensor_errors)[-3:]` to find the top 3 most anomalous sensors.
*   It passes these sensor IDs (e.g., `n33`, `n42`) to `zones.py`, which maps them to a physical sector of the network (e.g., "Zone 2").

---

## 3. Alerts & Push Notifications Workflow

How does a mathematical anomaly in Python become an alert on your phone?

### Automatic AI Alerts
1. When `/predict` yields `is_anomaly = True`, it saves a record to the `anomalies` table in the SQLite database.
2. The backend instantly uses the **Firebase Admin SDK** to craft an FCM (Firebase Cloud Messaging) payload.
3. It sends this payload to a **Topic**. Instead of managing thousands of individual device tokens, Firebase allows users to subscribe to topics. The backend sends the push to the topic matching the affected zone (e.g., `Zone_2`).
4. Google's FCM servers blast the notification to every mobile device subscribed to `Zone_2`.

### Manual Broadcast Alerts
1. An engineer on the web dashboard types a custom message (e.g., "Main valve shut off") and selects "Zone 4", then clicks "Send Broadcast".
2. The dashboard hits `POST /api/v1/broadcast`.
3. The backend saves a manual anomaly record and fires a Firebase push notification to the `Zone_4` topic containing the custom message.

### User Manual Reports
1. A regular user sees a puddle in the street. They open the app and use the "Report Issue" screen.
2. The app hits `POST /api/v1/report`. The report is saved to the DB.
3. Engineers looking at the Dashboard's "Reports" tab see this new issue populate in real-time. They can update its status from "Pending" to "Investigating" to "Resolved" (`PATCH /reports/{id}/status`).

---

## 4. Mobile App Event Handling & Native Alarms

The Flutter app has complex rules for ensuring you never miss a critical alert.

### Firebase Message Routing
*   **App is Open (Foreground):** FCM triggers `FirebaseMessaging.onMessage.listen()`. The app intercepts the data, prevents the OS default popup, and uses `flutter_local_notifications` to slide a custom heads-up banner down from the top of the screen.
*   **App is Closed (Background/Killed):** The Android OS handles the FCM payload natively, placing a notification in the system tray. If tapped, it wakes the app and passes the payload to `FirebaseMessaging.onMessageOpenedApp`.

### The "Red Screen" Race Condition Fix
A major workflow challenge was ensuring the full-screen red anomaly alert *always* appeared when tapping a notification, even if the app was completely killed.
*   **The Global Key:** We wired a `GlobalKey<NavigatorState>` directly to the `MaterialApp` in `main.dart`. This allows background callbacks (which don't have a `BuildContext`) to force the app to navigate to the red screen.
*   **App Resume Check:** We implemented a `WidgetsBindingObserver` in `UserHomeScreen`. Whenever the app transitions from "Background" to "Resumed", it instantly executes `Alarm.isRinging()`. If a leak alarm is active, it triggers the red screen *before* making any slow network calls.

### Water Outage Scheduling (Exact Alarms)
Leaks are sudden, but Outages are planned.
1. Engineers schedule an outage on the dashboard (`POST /outages`).
2. The mobile app fetches upcoming outages. The user clicks "Set Alarm".
3. The app uses the `alarm` package to schedule an Android `AlarmManager.setExactAndAllowWhileIdle()` intent for the exact start time.
4. **Permissions:** The app relies on `SCHEDULE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, and `SYSTEM_ALERT_WINDOW` permissions.
5. **Execution:** At the exact minute, even if the phone is asleep in Doze mode and the Flutter app is dead, the Android OS spins up a foreground service. It wakes the CPU (`WAKE_LOCK`), turns on the screen, plays a continuous looping siren `alarm.mp3`, and draws the red alert UI over the lock screen. The only way to stop it is for the user to physically tap "STOP ALARM".
