@echo off
title LeakLens Unified Launcher
color 0A

echo.
echo  =========================================
echo   LeakLens  ^|  Unified Launcher
echo  =========================================
echo.

REM 1. Start Backend in a separate persistent window
echo  [1/2] Starting FastAPI Backend...
start "LeakLens Backend" cmd /k "cd /d %~dp0backend && echo Starting backend... && (if exist venv\Scripts\python.exe (echo Using virtual environment... && venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000) else (echo Using system Python... && python -m uvicorn main:app --host 0.0.0.0 --port 8000)) || (echo. && echo BACKEND FAILED - CHECK ERRORS ABOVE && pause)"

REM 2. Wait for backend to initialize
timeout /t 8 /nobreak > nul

REM 3. Open Web Dashboard via HTTP (served by the backend — no CORS issues)
echo  [2/2] Opening Web Dashboard...
start "" "http://localhost:8000/dashboard"

echo.
echo  =========================================
echo   System is now RUNNING!
echo.
echo   - Backend:   http://localhost:8000
echo   - Dashboard: http://localhost:8000/dashboard
echo  =========================================
echo.
echo  NOTE: Keep the "LeakLens Backend" window open!
echo  If it closed, your backend is NOT running.
echo.
pause
