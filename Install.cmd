@echo off
:: Self-elevate to Administrator if needed, then run Install.ps1
net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~dpnx0\"' -Verb RunAs"
    exit /b
)
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Install.ps1"
pause
