# CareerPath – Installation, Setup & Running Guide (Document I)

This guide provides beginner-friendly, step-by-step instructions for installing, configuring, running, and demonstrating CareerPath on Windows.

---

## 1. Prerequisites Checklist

Ensure the following runtimes and tools are installed:
- **Python 3.12+**
- **Flutter SDK 3.27+ or 3.47+**
- **Android Studio** (with Android SDK 36 and Android Emulator)
- **Java Development Kit (JDK 17 or JDK 24)** (e.g., Oracle JDK 24 or Eclipse Adoptium Temurin JDK 17)
- **Google Chrome** (for web demonstration)

---

## 2. Setting Up the Python FastAPI Backend

### Step 2.1 – Navigate to Backend Workspace
Open PowerShell and navigate to the project directory:
```powershell
cd c:\Users\ambat\OneDrive\Desktop\careerpath\backend\careerpath
```

### Step 2.2 – Create and Activate Virtual Environment
```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
```

### Step 2.3 – Install Python Dependencies
```powershell
pip install -r requirements.txt
```

### Step 2.4 – Configure Environment Variables
Copy `.env.example` to `.env`:
```powershell
Copy-Item .env.example .env
```
Open `.env` and verify the settings:
```ini
ENVIRONMENT=development
HOST=0.0.0.0
PORT=8000
DEBUG=True

ALLOWED_ORIGINS=http://localhost:8000,http://127.0.0.1:8000,http://localhost:3000

FIREBASE_PROJECT_ID=careerpath-26fa0
FIREBASE_SERVICE_ACCOUNT_PATH=secrets/firebase_service_account.json

SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_SECRET_KEY=your-supabase-service-role-key
```

### Step 2.5 – Start the FastAPI Server
```powershell
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```
You should see:
```
INFO: Uvicorn running on http://0.0.0.0:8000
[INFO] Loaded 901 roles from master_roles.json
[INFO] Loaded 408 skills from skills_dictionary.json
```
Verify health in your browser at `http://127.0.0.1:8000/`.

---

## 3. Running CareerPath in Google Chrome (Web Mode)

Open a second PowerShell window:
```powershell
cd c:\Users\ambat\OneDrive\Desktop\careerpath\backend\careerpath
flutter run -d chrome --web-port 3000 --dart-define=BACKEND_URL=http://localhost:8000
```
Chrome will open `http://localhost:3000` with CareerPath running.

---

## 4. Running CareerPath on Android Emulator

### Step 4.1 – Launch the Android Emulator
```powershell
flutter emulators --launch Pixel_3a_API_36_extension_level_19_x86_64
```
Wait 20–30 seconds until the emulator boots to the Android home screen.

### Step 4.2 – Install and Run the Verified APK
In PowerShell:
```powershell
adb -s emulator-5554 install -r CareerPath_Final_Submission\CareerPath-debug.apk
```
Or launch directly using Flutter:
```powershell
flutter run -d emulator-5554
```

> [!NOTE]
> CareerPath features dynamic backend URL resolution. It automatically detects and connects to `http://10.0.2.2:8000` inside the Android emulator, and `http://127.0.0.1:8000` or local Wi-Fi on physical devices.

---

## 5. Running CareerPath on a Physical Android Phone (e.g. Samsung Galaxy S24 Ultra)

### Step 5.1 – Connect Device & Forward Port
Connect your physical Android phone via USB with USB Debugging enabled, or via Wireless ADB:
```powershell
adb devices
adb reverse tcp:8000 tcp:8000
```

### Step 5.2 – Install and Launch
```powershell
adb install -r CareerPath_Final_Submission\CareerPath-debug.apk
adb shell am start -n com.example.careerpath/.MainActivity
```
CareerPath will connect to `http://127.0.0.1:8000` (forwarded to your PC) or `http://192.168.1.5:8000` over your shared Wi-Fi.

---

## 6. Running Regression Tests

### Running Python Backend Tests:
```powershell
cd c:\Users\ambat\OneDrive\Desktop\careerpath\backend\careerpath
python -m pytest test_backend.py -v
```
Expected result: `52 passed`.

### Running Flutter Tests & Analyzer:
```powershell
flutter analyze
flutter test
```
Expected result: `No issues found!` and `All tests passed! (13/13)`.
