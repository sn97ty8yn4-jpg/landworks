@echo off
cd /d "%~dp0..\.."
where py >nul 2>nul
if %errorlevel%==0 (
  py -3 tools\get_models.py
) else (
  python tools\get_models.py
)
if errorlevel 1 (
  echo.
  echo Download or validation failed. Read docs\ASSET_SOURCES.md for manual download links.
)
echo.
pause
