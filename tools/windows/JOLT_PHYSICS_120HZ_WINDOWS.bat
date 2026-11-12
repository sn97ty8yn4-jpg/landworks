@echo off
cd /d "%~dp0..\.."
py -3 tools\select_physics.py jolt
pause
