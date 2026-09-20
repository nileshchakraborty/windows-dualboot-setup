@echo off
:: Self-elevate to Administrator if needed, then run Restart-To-Bazzite.ps1
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~dpnx0\"' -Verb RunAs"
    exit /b
)
powershell -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "%~dp0Restart-To-Bazzite.ps1"
