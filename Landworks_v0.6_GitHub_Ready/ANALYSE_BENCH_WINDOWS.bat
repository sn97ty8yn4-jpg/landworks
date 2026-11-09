@echo off
set /p SUMMARY=Path to landworks_comparison_summary.csv (from Godot user data folder):
if "%SUMMARY%"=="" (
 echo No file selected, no results were fabricated.
 pause
 exit /b 1
)
py -3 tools\analyse_tractor_bench.py "%SUMMARY%" --out landworks_tractor_comparison.md
pause
