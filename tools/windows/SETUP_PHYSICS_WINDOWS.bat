@echo off
cd /d "%~dp0..\.."
py -3 tools\setup_physics_vendors.py --vendor all
pause
