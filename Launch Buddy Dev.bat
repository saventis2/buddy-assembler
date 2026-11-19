@echo off
setlocal

:: ──────────────────────────────────────────────────────────────────
:: Buddy Runtime Launcher — Vertical Slice (Dev Mode)
:: Starts the standalone vertical-slice test scene with hotkeys.
:: ──────────────────────────────────────────────────────────────────

set "REPO=%~dp0"
set "GODOT_WINGET=%LOCALAPPDATA%\Microsoft\WinGet\Links\godot.exe"
set "PROJECT=%REPO%apps\runtime-godot"

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

echo Starting Buddy Dev (Vertical Slice)...
start "" "%GODOT%" --path "%PROJECT%" -- --vertical-slice
