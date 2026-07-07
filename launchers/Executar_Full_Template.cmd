@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Mega Backup WSL - Full Template

chcp 65001 >nul 2>nul

set "REPO_ROOT=%~dp0.."
set "SCRIPT=%REPO_ROOT%\scripts\Mega_Backup_WSL.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo [ERRO] Arquivo nao encontrado:
    echo %SCRIPT%
    echo.
    pause
    exit /b 1
)

pushd "%REPO_ROOT%" >nul 2>nul
if errorlevel 1 (
    echo.
    echo [ERRO] Nao foi possivel abrir a pasta do script:
    echo %REPO_ROOT%
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo        MEGA BACKUP WSL - FULL TEMPLATE EM 2 ETAPAS
echo ============================================================
echo.
echo [1/2] Purificar e validar distros como template
echo       Comando: -BackupMode Distros -PurifyOnly -QualityGate Template
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%SCRIPT%" -BackupMode Distros -PurifyOnly -QualityGate Template %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo ============================================================
    echo [ERRO] A purificacao Template falhou. Codigo: %EXIT_CODE%
    echo        O backup completo nao foi iniciado.
    echo        Verifique a pasta de logs configurada no script.
    echo ============================================================
    echo.
    popd >nul
    pause
    exit /b %EXIT_CODE%
)

echo.
echo ============================================================
echo [OK] Purificacao Template aprovada.
echo ============================================================
echo.
echo [2/2] Backup completo com QualityGate Template
echo       Comando: -BackupMode All -QualityGate Template
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "%SCRIPT%" -BackupMode All -QualityGate Template %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo ============================================================

if "%EXIT_CODE%"=="0" (
    echo [OK] Fluxo Full Template concluido com sucesso.
) else (
    echo [ERRO] Backup completo falhou. Codigo: %EXIT_CODE%
    echo        Verifique a pasta de logs configurada no script.
)

echo ============================================================
echo.

popd >nul
pause
exit /b %EXIT_CODE%
