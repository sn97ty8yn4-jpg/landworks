@echo off
cd /d "%~dp0"
set "GODOT_EXE=%~1"
if "%GODOT_EXE%"=="" set "GODOT_EXE=godot"
python tools\run_work_tests.py --godot "%GODOT_EXE%" --out "%CD%\field_test_results"
if errorlevel 1 (
  echo TESTS NOT COMPLETE. Check Godot path and the test logs.
  pause
  exit /b 1
)
python tools\analyse_work_tests.py --dir "%CD%\field_test_results"
pause
