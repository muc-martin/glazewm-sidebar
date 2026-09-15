@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1"
if errorlevel 1 (
  echo Uninstall could not complete. See the message above. Your configuration backup is retained.
  pause
  exit /b 1
)
