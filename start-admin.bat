@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Demande d'elevation administrateur...
    powershell -NoProfile -Command "Start-Process -FilePath '%~dp0_run-elevated.bat' -Verb RunAs"
    exit
)

cd /d "%~dp0"
npm start
