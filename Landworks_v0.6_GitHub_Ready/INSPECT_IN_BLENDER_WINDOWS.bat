@echo off
setlocal
cd /d "%~dp0"
where blender.exe >NUL 2>NUL
if errorlevel 1 (
 echo Blender was not found on PATH. Launch a terminal using the installed blender.exe full path.
 echo Example: "C:\Program Files\Blender Foundation\Blender 4.4\blender.exe" --background --python tools\rigging\blender_rig.py -- --stage inspect --machine b7100
 pause
 exit /b 1
)
blender.exe --background --python tools\rigging\blender_rig.py -- --stage inspect --machine b7100
if errorlevel 1 goto fail
blender.exe --background --python tools\rigging\blender_rig.py -- --stage inspect --machine kx080
if errorlevel 1 goto fail
echo.
echo Open workbench\b7100.blend and workbench\kx080.blend in Blender and separate or group moving parts.
echo Copy exact mesh names to tools\rigging\recipes\b7100.json and kx080.json.
pause
exit /b 0
:fail
echo Blender inspection failed; see error above.
pause
exit /b 1
