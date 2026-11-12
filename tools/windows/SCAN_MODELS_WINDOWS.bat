@echo off
setlocal
cd /d "%~dp0..\.."
echo [Landworks] Scan the two CC0 GLB source files. No downloads performed.
python tools\rigging\scan_glb.py --machine b7100
if errorlevel 1 goto fail
python tools\rigging\scan_glb.py --machine kx080
if errorlevel 1 goto fail
echo.
echo Created rig mapping worksheets in tools\rigging\recipes\
echo Inspect mesh names in landworks\assets\reports\
echo Next: run INSPECT_IN_BLENDER_WINDOWS.bat and open the created .blend files.
pause
exit /b 0
:fail
echo.
echo Input file missing or not a valid GLB. Run DOWNLOAD_MODELS_WINDOWS.bat first.
pause
exit /b 1
