#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $repoRoot "src\MegaBackupWsl.FastWpf"
$distDir = Join-Path $repoRoot "dist"
$outputPath = Join-Path $distDir "MegaBackupWsl.exe"
$iconPath = Join-Path $repoRoot "assets\mega-backup-wsl.ico"
$compiler = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"

if (-not (Test-Path -LiteralPath $compiler)) {
    throw "Compilador C# nao encontrado: $compiler"
}

if (-not (Test-Path -LiteralPath $sourceDir)) {
    throw "Diretorio fonte nao encontrado: $sourceDir"
}

$sourceFiles = @(
    Get-ChildItem -LiteralPath $sourceDir -Filter "*.cs" -File |
        Sort-Object FullName |
        Select-Object -ExpandProperty FullName
)

if ($sourceFiles.Count -eq 0) {
    throw "Nenhum fonte C# encontrado em: $sourceDir"
}

$references = @(
    (Join-Path $env:WINDIR "Microsoft.NET\assembly\GAC_MSIL\PresentationFramework\v4.0_4.0.0.0__31bf3856ad364e35\PresentationFramework.dll"),
    (Join-Path $env:WINDIR "Microsoft.NET\assembly\GAC_64\PresentationCore\v4.0_4.0.0.0__31bf3856ad364e35\PresentationCore.dll"),
    (Join-Path $env:WINDIR "Microsoft.NET\assembly\GAC_MSIL\WindowsBase\v4.0_4.0.0.0__31bf3856ad364e35\WindowsBase.dll"),
    (Join-Path $env:WINDIR "Microsoft.NET\assembly\GAC_MSIL\System.Xaml\v4.0_4.0.0.0__b77a5c561934e089\System.Xaml.dll")
)

foreach ($reference in $references) {
    if (-not (Test-Path -LiteralPath $reference)) {
        throw "Referencia WPF nao encontrada: $reference"
    }
}

New-Item -ItemType Directory -Path $distDir -Force | Out-Null

$referenceArgs = @(
    "/reference:System.dll",
    "/reference:System.Core.dll",
    "/reference:System.Windows.Forms.dll"
)

foreach ($reference in $references) {
    $referenceArgs += "/reference:$reference"
}

$iconArgs = @()
if (Test-Path -LiteralPath $iconPath) {
    $iconArgs += "/win32icon:$iconPath"
}

& $compiler `
    /nologo `
    /target:winexe `
    /platform:x64 `
    "/out:$outputPath" `
    @iconArgs `
    @referenceArgs `
    @sourceFiles

if ($LASTEXITCODE -ne 0) {
    throw "Falha ao compilar MegaBackupWsl.exe. Codigo: $LASTEXITCODE"
}

Get-Item -LiteralPath $outputPath
