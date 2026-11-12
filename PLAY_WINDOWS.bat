@echo off
setlocal
cd /d "%~dp0"
set "LANDWORKS_ENGINE=%~dp0runtime\Godot_v4.6.3-stable_win64.exe"
if exist "%LANDWORKS_ENGINE%" goto play
where godot.exe >nul 2>nul
if not errorlevel 1 (
  set "LANDWORKS_ENGINE=godot.exe"
  goto play
)
echo This source-only copy needs Godot 4.6.3.
echo Open project.godot in Godot and press F5, or use the Windows playable ZIP.
pause
exit /b 1
:play
if not exist "%~dp0validation\logs" mkdir "%~dp0validation\logs"
rem Import on launch so newly integrated models and textures are not skipped.
if exist "project.godot" (
  echo Preparing game assets for the first launch...
  "%LANDWORKS_ENGINE%" --headless --path "%~dp0." --editor --import --quit --log-file "%~dp0validation\logs\first_launch.log"
  if errorlevel 1 (
    echo Asset preparation failed. See validation\logs\first_launch.log.
    pause
    exit /b 1
  )
)
start "Landworks" "%LANDWORKS_ENGINE%" --path "%~dp0." --rendering-method gl_compatibility
endlocal
