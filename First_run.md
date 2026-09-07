# 🚀 First Run Guide — LeakLens

Welcome to the LeakLens project! Follow this step-by-step guide to get everything installed, running, and connected on your devices for the first time.

---

## 1️⃣ Install Prerequisites & Dependencies

You need to set up the environments for both the Python Backend and the Flutter Mobile App.

### Backend Setup (Python)
1. Ensure you have Python 3.9 or higher installed.
2. Open your terminal or command prompt in the project root.
3. Navigate to the backend folder and install the dependencies:
   ```bash
   cd backend
   python -m venv venv
   venv\Scripts\activate
   pip install -r requirements.txt
   ```

### Mobile Setup (Flutter)
To install the app on your phone, **you must install Flutter** to build the APK (the built app is not included in the repository).
1. Ensure you have the Flutter SDK installed on your computer.
2. Navigate to the mobile folder and install packages:
   ```bash
   cd mobile
   flutter pub get
   ```

---

## 2️⃣ How to Run the Server & Find Your IPv4 Address

To connect your mobile phone to your local computer, they **must be on the same Wi-Fi network**, and you need your computer's local IP address (IPv4).

### Find your IPv4 Address (Windows)
1. Open a new Command Prompt (`cmd`).
2. Type the following command and press Enter:
   ```cmd
   ipconfig
   ```
3. Look for the line that says **IPv4 Address** under your active Wi-Fi or Ethernet adapter. It will look something like `192.168.1.15`. **Save this number.**

### Start the Server
1. Double-click the `run_system.bat` file in the main project folder.
2. *Alternatively*, via terminal:
   ```bash
   cd backend
   python main.py
   ```
3. The server is now running on your computer at `http://0.0.0.0:8000`.

---

## 3️⃣ How to Take the Mobile App to Your Phone

Because the raw code is provided, you need to build the APK file and transfer it to your Android device.

1. Open a terminal in the `mobile` folder.
2. Build the Android release APK (we disable tree-shaking to prevent cache errors):
   ```bash
   flutter build apk --no-tree-shake-icons
   ```
3. Once the build succeeds, you will find the APK file here:
   `mobile\build\app\outputs\flutter-apk\app-release.apk`
4. Connect your Android phone to your computer via USB.
5. Copy the `app-release.apk` file to your phone's storage (e.g., into the Downloads folder).
6. On your phone, open your File Manager, tap the APK, and select **Install**. 
   *(Note: You may need to allow "Install from unknown sources" in your Android settings).*

---

## 4️⃣ Connecting the Mobile App to the Server

1. Ensure your phone is connected to the **same Wi-Fi network** as your computer.
2. Open the LeakLens app on your phone.
3. On the login or role selection screen, look for the **Backend URL** or **Settings** field.
4. Enter your computer's IPv4 address with port 8000 like this:
   `http://<YOUR_IPV4_ADDRESS>:8000`
   *(Example: `http://192.168.1.15:8000`)*

---

## 5️⃣ How to Add a New User or Engineer

### Default Admin Account
When you run the backend server for the very first time, it automatically creates a default Engineer account for testing:
* **Engineer ID:** `ENG-001`
* **Password:** `admin123`

### How to Add a New Engineer
Engineers are staff members and must be added via the Web Dashboard.
1. Open the Web Dashboard by simply double-clicking `dashboard/index.html` in your browser.
2. Look at the top right corner of the header and click the **"+ Add Engineer"** button.
3. Fill out the form with a new ID, Name, and Password.

### How to Add a New User
Citizens/Users can create their own accounts directly from the mobile app.
1. Open the LeakLens Mobile App.
2. Tap on the **User** role card.
3. Tap **Register** at the bottom of the login screen.
4. Fill in the required details (Name, Phone, Email, Zone, Password) and submit.
