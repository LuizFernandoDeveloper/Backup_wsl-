@echo off
setlocal EnableExtensions
title Backup WSL_Drives.vhdx

set "RUNNER=%~dp0Executar_Mega_Backup_WSL.cmd"

if not exist "%RUNNER%" (
    echo.
    echo [ERRO] Arquivo nao encontrado:
    echo %RUNNER%
    echo.
    pause
    exit /b 1
)

call "%RUNNER%" -BackupMode Vhdx %*

exit /b %ERRORLEVEL%
