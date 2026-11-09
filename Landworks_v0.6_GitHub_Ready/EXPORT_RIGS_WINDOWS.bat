@echo off
setlocal
cd /d "%~dp0"
where blender.exe >NUL 2>NUL
if errorlevel 1 (
 echo Blender not on PATH; see docs\RIGGING_GUIDE.md for command-line instructions.
 pause
 exit /b 1
)
if not exist "landworks\assets\workbench\b7100.blend" goto nowork
if not exist "landworks\assets\workbench\kx080.blend" goto nowork
echo This intentionally fails if any part has not been assigned in the recipes.
blender.exe --background "landworks\assets\workbench\b7100.blend" --python tools\rigging\blender_rig.py -- --stage export --machine b7100
if errorlevel 1 goto fail
blender.exe --background "landworks\assets\workbench\kx080.blend" --python tools\rigging\blender_rig.py -- --stage export --machine kx080
if errorlevel 1 goto fail
echo.
echo Exported to landworks\assets\rigged\ . Check in the Godot test yard with F3 pivot guides.
pause
exit /b 0
:nowork
echo Run INSPECT_IN_BLENDER_WINDOWS.bat first to create the source .blend workbenches.
pause
exit /b 1
:fail
echo One or more parts could not be exported. Check object names and pivots in the JSON recipe.
pause
exit /b 1
