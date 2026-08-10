@echo off
title Win11 NetOptimizer Launcher
:: Comprobar si el script .ps1 existe en el mismo directorio que este .bat
set "SCRIPT_DIR=%~dp0"
set "PS1_FILE=%SCRIPT_DIR%Win11-NetOptimizer.ps1"

if not exist "%PS1_FILE%" (
    echo [ERROR] No se encuentra Win11-NetOptimizer.ps1 en el mismo directorio.
    pause
    exit /b 1
)

:: Verificar permisos de administrador
net session >nul 2>&1
if %errorLevel% neq 0 (
    :: Solicitar elevacion UAC (ventana oculta)
    powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -WindowStyle Hidden -File \"%PS1_FILE%\"' -Verb RunAs"
    exit /b 0
)

:: Ya somos admin, ejecutar directamente (ventana oculta)
powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS1_FILE%"
exit /b 0