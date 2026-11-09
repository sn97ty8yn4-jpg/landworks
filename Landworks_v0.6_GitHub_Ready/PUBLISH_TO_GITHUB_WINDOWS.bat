@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PUBLISH_TO_GITHUB_WINDOWS.ps1"
if errorlevel 1 pause
