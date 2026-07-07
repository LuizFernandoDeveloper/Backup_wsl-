@echo off
setlocal EnableExtensions
title Mega Backup WSL - Seguro

set "SCRIPT=%~dp0Mega_Backup_WSL.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo [ERRO] Arquivo nao encontrado:
    echo %SCRIPT%
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo              MEGA BACKUP WSL - INICIANDO
echo ============================================================
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%SCRIPT%" %*

set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo ============================================================

if "%EXIT_CODE%"=="0" (
    echo [OK] Backup concluido com sucesso.
) else (
    echo [ERRO] Backup terminou com codigo: %EXIT_CODE%
    echo Verifique a pasta logs dentro do BackupRoot configurado.
)

echo ============================================================
echo.
pause

exit /b %EXIT_CODE%
