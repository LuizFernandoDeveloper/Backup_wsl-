@echo off
setlocal EnableExtensions
title Mega Backup WSL - Interface

set "REPO_ROOT=%~dp0.."
set "PROJECT=%REPO_ROOT%\src\MegaBackupWsl.App\MegaBackupWsl.App.csproj"
set "EXE=%REPO_ROOT%\src\MegaBackupWsl.App\bin\Release\net8.0-windows\MegaBackupWsl.exe"

if exist "%EXE%" (
    start "" "%EXE%"
    exit /b 0
)

echo.
echo ============================================================
echo             MEGA BACKUP WSL - INTERFACE WPF
echo ============================================================
echo.
echo O executavel ainda nao foi compilado.
echo Projeto:
echo %PROJECT%
echo.

where dotnet >nul 2>nul
if errorlevel 1 (
    echo [ERRO] dotnet nao encontrado.
    echo Instale o .NET 8 SDK e rode este launcher novamente.
    echo.
    pause
    exit /b 1
)

dotnet --list-sdks | findstr /R "^[0-9]" >nul 2>nul
if errorlevel 1 (
    echo [ERRO] O .NET Runtime esta instalado, mas o .NET SDK nao foi encontrado.
    echo Instale o .NET 8 SDK para compilar a interface WPF.
    echo.
    echo Download:
    echo https://dotnet.microsoft.com/download
    echo.
    pause
    exit /b 1
)

echo Compilando interface...
dotnet build "%PROJECT%" -c Release
if errorlevel 1 (
    echo.
    echo [ERRO] Falha ao compilar a interface.
    echo.
    pause
    exit /b 1
)

if exist "%EXE%" (
    start "" "%EXE%"
    exit /b 0
)

echo.
echo [ERRO] Build concluiu, mas o executavel esperado nao foi encontrado:
echo %EXE%
echo.
pause
exit /b 1
