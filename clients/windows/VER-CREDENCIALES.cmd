@echo off
setlocal
title Asystec - Ver credenciales de RustDesk
if not exist "%~dp0Instalar-Asystec.ps1" (
  echo ERROR: Falta Instalar-Asystec.ps1. Extrae el ZIP completo.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Instalar-Asystec.ps1" -ShowCredentials
set "ASYSTEC_RESULT=%ERRORLEVEL%"
if not "%ASYSTEC_RESULT%"=="0" pause
exit /b %ASYSTEC_RESULT%
