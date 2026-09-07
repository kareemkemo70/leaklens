# LeakLens — Libraries, Methods & Implementation Strategies

This document provides a concise technical summary of the specific libraries and methodologies used to build each core component of the LeakLens system.

---

## 1. Server & Deployment (Backend)
The backend is built with **FastAPI**, a modern, high-performance Python web framework.

### Core Libraries
*   **FastAPI:** Used for the REST API. It was chosen for its native async support, automatic Swagger documentation (`/docs`), and speed.
*   **Uvicorn:** The ASGI server that runs the FastAPI application.
*   **SQLAlchemy + aiosqlite:** The Object-Relational Mapper (ORM) used to interact with the SQLite database asynchronously.
*   **Pydantic:** Used for data validation and settings management. It ensures that every request body matches our expected schema before the code even runs.
*   **python-jose:** Used to generate and verify **JWT (JSON Web Tokens)** for secure authentication.
*   **passlib[bcrypt]:** Used for securely hashing and verifying passwords.

### Deployment "Ways"
*   **Middleware:** We implemented custom middleware to log request timing (Performance tracking) and handle CORS (allowing the Dashboard and Flutter app to talk to the server).
*   **Lifespan Management:** We use FastAPI's `lifespan` hook to initialize Firebase, create database tables, and seed the default Engineer account (`ENG-001`) automatically on startup.
*   **Service-Oriented Routes:** The API is split into clean routers (`/predict`, `/auth`, `/reports`, etc.) to keep the codebase maintainable.

---

## 2. Mobile Application (Flutter)
The mobile app is a cross-platform native application built using **Flutter**.

### Core Libraries
*   **Provider:** The primary state management solution. It keeps the UI in sync with the data.
*   **http:** Used for all communication with the FastAPI backend.
*   **fl_chart:** Used to render the high-performance charts in the Engineer's Analytics tab.
*   **animate_do:** Used for the smooth "Fade-In" and "Zoom" animations on the dashboard.
*   **Google Fonts (Inter):** Used to provide a consistent, professional typography across the app.
*   **shared_preferences:** Used to store the login token and user role locally so you don't have to log in every time you open the app.

---

## 3. Data Generators (Simulation)
Since there are no real pipes in the demo, the **Simulator** is responsible for creating realistic water network behavior.

### Core Methods
*   **NumPy:** The "engine" behind the generators. It handles the heavy matrix math needed to create 48-minute windows for 119 sensors.
*   **AR(1) Process (Auto-Regressive):** Used in the **Synthetic Generator**. It ensures that if the pressure was 5.0 last minute, it will be around 5.0 this minute (momentum), but with a slight pull back toward the average (gravity).
*   **IQR-Scaled Drops:** For the "Real Leak" mode, we calculate the **Interquartile Range** of each sensor to ensure the pressure drop is "physically plausible" for that specific sensor's historical behavior.
*   **Exponential Ramps:** In "Synthetic Leak" mode, we apply a `t^1.5` drop. This mimics the physics of a pipe burst, where the hole starts small and gets bigger very quickly.

---

## 4. Notifications & Alarms
This is the most complex part of the system, involving a bridge between Python and Mobile OS internals.

### Core Libraries
*   **firebase_admin (Python):** Used on the server to send messages. We use **Topic-Based Messaging** (sending to `Zone_1` instead of specific phones) to make the system scalable.
*   **firebase_messaging (Flutter):** Receives the push notifications.
*   **flutter_local_notifications:** Used to show the "Heads-Up" banner when the app is open.
*   **alarm (Flutter):** This is the key to our **Persistent Outage Alarms**. It uses Android's `AlarmManager` to ensure the siren plays even if the app is killed or the phone is in "Doze" mode.

### The "Ways" we solved Notification issues
*   **GlobalKey Navigation:** We created a `GlobalKey<NavigatorState>` in `main.dart`. This allows the background notification code to "force" the app to change screens to the red emergency UI, even if the user is currently on a different page.
*   **WidgetsBindingObserver:** We added a lifecycle observer to the home screen. Every time you minimize and then **Maximize (Resume)** the app, it instantly checks `Alarm.isRinging()`. This ensures that if you tap a notification to open the app, the red alarm screen appears immediately without waiting for the network.
*   **Full-Screen Intent:** We configured the Android Manifest to allow **Full-Screen Intents**. This is what allows the red alarm screen to "jump" over the lock screen and wake up the phone when a leak is detected.

---
