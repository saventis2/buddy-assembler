@echo off
setlocal

:: ──────────────────────────────────────────────────────────────────
:: Buddy Runtime — Headless Test Gate
:: Runs all automated checks (parse, smoke, save, pack, behavior).
:: ──────────────────────────────────────────────────────────────────

set "SCRIPT=%~dp0apps\runtime-godot\tests\run_headless_checks.ps1"

if not exist "%SCRIPT%" (
    echo ERROR: Test script not found: %SCRIPT%
    pause
    exit /b 1
)

echo Running headless verification gate...
pwsh -NoLogo -File "%SCRIPT%"

if %ERRORLEVEL% == 0 (
    echo.
    echo [PASS] All checks passed.
) else (
    echo.
    echo [FAIL] One or more checks failed. See output above.
)

pause
