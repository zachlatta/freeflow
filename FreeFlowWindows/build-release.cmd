@echo off
REM FreeFlow Windows - Release Build Script (Batch wrapper)
REM Run this to create release builds

echo.
echo FreeFlow Windows - Release Build
echo ================================
echo.

REM Check if PowerShell is available
where powershell >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: PowerShell is required to run this build script.
    pause
    exit /b 1
)

REM Run the PowerShell build script
powershell -ExecutionPolicy Bypass -File "%~dp0build-release.ps1" %*

if %ERRORLEVEL% neq 0 (
    echo.
    echo Build failed with error code %ERRORLEVEL%
    pause
    exit /b %ERRORLEVEL%
)

echo.
pause
