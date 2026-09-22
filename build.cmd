@echo off
setlocal enabledelayedexpansion

echo ========================================================
echo   Building RestartToBazzite.exe
echo ========================================================

:: Check for dotnet CLI
where dotnet >nul 2>&1
if %errorLevel% equ 0 (
    echo [*] Found .NET SDK. Building solution with dotnet...
    dotnet build "%~dp0RestartToBazzite.sln" -c Release
    if %errorLevel% equ 0 (
        echo [OK] Build succeeded via dotnet!
        goto :done
    )
)

:: Fallback: Check for MSBuild in Visual Studio installations
set MSBUILD_EXE=
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe 2^>nul`) do (
    set "MSBUILD_EXE=%%i"
)

if defined MSBUILD_EXE (
    echo [*] Found MSBuild at: !MSBUILD_EXE!
    "!MSBUILD_EXE!" "%~dp0RestartToBazzite.sln" /p:Configuration=Release
    if !errorLevel! equ 0 (
        echo [OK] Build succeeded via MSBuild!
        goto :done
    )
)

:: Fallback: Built-in .NET Framework csc.exe (preinstalled on 100% of Windows 10/11 machines)
set CSC_EXE=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC_EXE%" set CSC_EXE=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe

if exist "%CSC_EXE%" (
    echo [*] Building via built-in Windows .NET Framework compiler: %CSC_EXE%
    if not exist "%~dp0src\RestartToBazzite\bin\Release\net48" mkdir "%~dp0src\RestartToBazzite\bin\Release\net48"
    "%CSC_EXE%" /target:winexe /optimize+ /win32manifest:"%~dp0src\RestartToBazzite\app.manifest" /win32icon:"%~dp0src\RestartToBazzite\RestartToBazzite.ico" /r:System.Windows.Forms.dll /r:System.Drawing.dll /out:"%~dp0src\RestartToBazzite\bin\Release\net48\RestartToBazzite.exe" "%~dp0src\RestartToBazzite\Program.cs"
    if !errorLevel! equ 0 (
        echo [OK] Build succeeded via csc.exe!
        goto :done
    )
)

echo [ERROR] No suitable compiler found (dotnet, MSBuild, or csc.exe).
exit /b 1

:done
echo.
echo Binary located at:
dir /b /s "%~dp0src\RestartToBazzite\bin\Release\RestartToBazzite.exe" 2>nul
echo ========================================================
