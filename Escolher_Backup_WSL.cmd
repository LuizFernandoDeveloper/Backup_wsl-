@echo off
setlocal EnableExtensions
title Escolher Backup WSL

set "RUNNER=%~dp0Executar_Mega_Backup_WSL.cmd"

if not exist "%RUNNER%" (
    echo.
    echo [ERRO] Arquivo nao encontrado:
    echo %RUNNER%
    echo.
    pause
    exit /b 1
)

:MENU
cls
echo.
echo ============================================================
echo                  ESCOLHER BACKUP WSL
echo ============================================================
echo.
echo  1. Backup completo: distros + WSL_Drives.vhdx
echo  2. Somente distros WSL
echo  3. Somente WSL_Drives.vhdx
echo  4. Testar completo sem copiar nada
echo  5. Sair
echo.

choice /C 12345 /N /M "Escolha uma opcao [1-5]: "

if errorlevel 5 exit /b 0
if errorlevel 4 call "%RUNNER%" -BackupMode All -DryRun %*
if errorlevel 3 call "%RUNNER%" -BackupMode Vhdx %*
if errorlevel 2 call "%RUNNER%" -BackupMode Distros %*
if errorlevel 1 call "%RUNNER%" -BackupMode All %*

exit /b %ERRORLEVEL%
