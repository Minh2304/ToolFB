@echo off
where node >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  node "%~dp0native_host.cjs"
) else (
  powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0native_host.ps1"
)
