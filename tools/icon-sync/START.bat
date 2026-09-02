@echo off
setlocal
title iPadProCAD - Icon Preview
cd /d "%~dp0"

echo.
echo   iPadProCAD - Icon Preview
echo   =========================
echo.

rem ---- find a Python that actually runs --------------------------------
rem Not `where py`: on a fresh Windows that finds the Microsoft Store stub,
rem which exits 9009 and opens the Store instead of running anything. Asking
rem it to import something is the only honest test.
set PY=
py -c "import sys" >nul 2>&1
if not errorlevel 1 set PY=py
if not defined PY (
  python -c "import sys" >nul 2>&1
  if not errorlevel 1 set PY=python
)
if not defined PY (
  echo   Python is not installed.
  echo.
  echo   Get it from  https://www.python.org/downloads/
  echo   IMPORTANT: tick "Add python.exe to PATH" in the installer,
  echo   then run this file again.
  echo.
  pause
  exit /b 1
)

rem ---- make sure Pillow is there ----------------------------------------
%PY% -c "import PIL" >nul 2>&1
if errorlevel 1 (
  echo   First run - installing Pillow. This takes a moment...
  %PY% -m pip install --quiet --disable-pip-version-check pillow
  if errorlevel 1 (
    echo.
    echo   Could not install Pillow.
    echo   Try right-clicking this file and choosing "Run as administrator".
    echo.
    pause
    exit /b 1
  )
  echo   ...done.
  echo.
)

if not exist "renders" mkdir "renders"

echo   Point Blender's output at this folder:
echo.
echo       %CD%\renders
echo.
echo   If Windows asks about the firewall: tick PRIVATE networks, then Allow.
echo   Without that the iPad cannot reach this PC.
echo.

%PY% serve.py "%CD%\renders"

echo.
pause
