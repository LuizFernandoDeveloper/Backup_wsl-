@echo off
setlocal EnableExtensions
title Mega Backup WSL - Seguro

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
    echo [ERRO] Nao foi possivel abrir a pasta do projeto:
    echo %REPO_ROOT%
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

popd >nul
exit /b %EXIT_CODE%
