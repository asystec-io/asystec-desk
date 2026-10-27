@echo off
setlocal
title Asystec - Instalar RustDesk
echo.
echo Se instalara RustDesk y se configurara para soporte con Asystec.
echo Servidor: 184.197.59.221
echo Se asignara una contrasena permanente distinta para cada equipo.
echo Al repetir la instalacion se reutilizara la contrasena guardada.
echo.
echo Extrae primero TODOS los archivos del ZIP en una carpeta.
echo Guarda tu trabajo y cierra cualquier sesion remota de RustDesk.
echo.
if not exist "%~dp0Instalar-Asystec.ps1" (
  echo ERROR: Falta Instalar-Asystec.ps1. Extrae el ZIP completo.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Instalar-Asystec.ps1"
set "ASYSTEC_RESULT=%ERRORLEVEL%"
if "%ASYSTEC_RESULT%"=="3010" (
  echo Instalacion completada. Windows solicita reiniciar el equipo.
  set "ASYSTEC_RESULT=0"
)
echo.
if "%ASYSTEC_RESULT%"=="0" (
  echo Proceso completado. Abre RustDesk desde el escritorio.
) else (
  echo No se completo la instalacion. Envia el mensaje anterior a Asystec.
)
pause
exit /b %ASYSTEC_RESULT%
