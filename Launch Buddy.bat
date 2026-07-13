@echo off
setlocal

:: ──────────────────────────────────────────────────────────────────
:: Buddy Runtime Launcher
:: Double-click this file to start the buddy companion overlay.
:: ──────────────────────────────────────────────────────────────────

set "REPO=%~dp0"
set "GODOT_WINGET=%LOCALAPPDATA%\Microsoft\WinGet\Links\godot.exe"
set "PROJECT=%REPO%apps\runtime-godot"

:: Resolve godot: prefer PATH, fall back to WinGet install
where godot >nul 2>&1
if %ERRORLEVEL% == 0 (
    set "GODOT=godot"
) else if exist "%GODOT_WINGET%" (
    set "GODOT=%GODOT_WINGET%"
) else (
    echo ERROR: Godot not found.
    echo Install Godot 4 via WinGet:  winget install GodotEngine.GodotEngine
    pause
    exit /b 1
)

echo Starting Buddy Runtime...
start "" "%GODOT%" --path "%PROJECT%"
