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
echo  2. Backup completo + limpar sockets temporarios
echo  3. Somente distros WSL
echo  4. Somente WSL_Drives.vhdx
echo  5. Saude leve das distros
echo  6. Diagnostico pesado das distros
echo  7. Validar distros como template
echo  8. Purificar template sem backup
echo  9. Testar completo sem copiar nada
echo  A. Organizar diretorios de backup ja publicados
echo  0. Sair
echo.

choice /C 123456789A0 /N /M "Escolha uma opcao [1-9,A,0]: "

if errorlevel 11 exit /b 0
if errorlevel 10 call "%RUNNER%" -OrganizeRuns %*
if errorlevel 9 call "%RUNNER%" -BackupMode All -DryRun %*
if errorlevel 8 call "%RUNNER%" -BackupMode Distros -PurifyOnly -QualityGate Template %*
if errorlevel 7 call "%RUNNER%" -BackupMode Distros -HealthOnly -QualityGate Template %*
if errorlevel 6 call "%RUNNER%" -BackupMode Distros -HealthOnly -DeepHealth %*
if errorlevel 5 call "%RUNNER%" -BackupMode Distros -HealthOnly %*
if errorlevel 4 call "%RUNNER%" -BackupMode Vhdx %*
if errorlevel 3 call "%RUNNER%" -BackupMode Distros %*
if errorlevel 2 call "%RUNNER%" -BackupMode All -CleanWslSockets %*
if errorlevel 1 call "%RUNNER%" -BackupMode All %*

exit /b %ERRORLEVEL%
