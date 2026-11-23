@echo off
cd /d "%~dp0..\.."
set "GODOT_EXE=%~1"
if "%GODOT_EXE%"=="" set "GODOT_EXE=%~dp0..\..\runtime\Godot_v4.6.3-stable_win64_console.exe"
if not exist "%GODOT_EXE%" set "GODOT_EXE=godot"
rem Find a Python. A stock Windows install has the "py" launcher and no
rem "python" on PATH at all — the App Execution Alias answers "python" with
rem a Store advert and exit code 49 — so py is tried first.
set "PY_EXE="
for %%P in (py python python3) do (
  if not defined PY_EXE (
    %%P -c "import sys" >nul 2>nul && set "PY_EXE=%%P"
  )
)
if not defined PY_EXE (
  echo No working Python found. Install Python 3 and try again.
  pause
  exit /b 1
)
%PY_EXE% tools\run_work_tests.py --godot "%GODOT_EXE%" --out "%CD%\field_test_results"
if errorlevel 1 (
  echo TESTS NOT COMPLETE. Check Godot path and the test logs.
  pause
  exit /b 1
)
%PY_EXE% tools\analyse_work_tests.py --dir "%CD%\field_test_results"
rem The gate CI actually fails on. Running the trials without this only
rem produces numbers; this is what judges them.
%PY_EXE% tools\validate_physics.py --dir "%CD%\field_test_results"
if errorlevel 1 (
  echo MEASURED PHYSICS OUTSIDE LIMITS. This is what CI rejects.
  pause
  exit /b 1
)
pause
