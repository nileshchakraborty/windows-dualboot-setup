@echo off
:: Ensure Windows Boot Manager is primary while in Windows session
bcdedit /set {fwbootmgr} displayorder {bootmgr} {7f9fafdd-7fe2-11f1-8f8e-806e6f6e6963} >nul 2>&1
