#requires -Version 5.1
<#
    MEGA BACKUP WSL

    Backup seguro, versionado e validado para distros WSL e, opcionalmente,
    um VHDX extra de laboratorio.

    Melhorias principais:
    - Parametros para destino, VHDX, retencao e reserva de espaco.
    - Modo -DryRun com inventario e estimativa, sem exportar nem copiar.
    - Escolha de modo: All, Distros ou Vhdx.
    - Retomada automatica de backup interrompido em _staging.
    - Opcao -SkipVhdx mantida por compatibilidade.
    - Estimativa conservadora de espaco usando os ext4.vhdx das distros.
    - Staging: so publica o backup depois de validar arquivos e hashes.
    - SHA-256 para TARs e VHDX.
    - Manifesto JSON, checksums e guia de restauracao.
    - Lock para impedir duas execucoes simultaneas.
    - Retencao limitada aos diretorios de backup criados pelo script.
#>

[CmdletBinding()]
param(
    [string]$BackupRoot = "F:\Backup\WSl_backup",
    [string]$SourceVhdx = "D:\disk-removivel-wsl2\WSL_Drives.vhdx",
    [string]$ExpectedVolumeLabel = "",

    [ValidateRange(1, 100)]
    [int]$KeepLastRuns = 3,

    [ValidateRange(1, 100000)]
    [int]$MinimumFreeSpaceGB = 25,

    [ValidateSet("All", "Distros", "Vhdx")]
    [string]$BackupMode = "All",

    [switch]$IncludeDocker,
    [switch]$SkipVhdx,
    [switch]$NoResume,
    [string]$ResumeRunId,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Config = [ordered]@{
    BackupRoot           = $BackupRoot
    SourceVhdx           = $SourceVhdx
    ExpectedVolumeLabel  = $ExpectedVolumeLabel
    KeepLastRuns         = $KeepLastRuns
    MinimumFreeSpaceGB   = $MinimumFreeSpaceGB
    HashAlgorithm        = "SHA256"
    IncludeDocker        = [bool]$IncludeDocker
    SkipVhdx             = [bool]$SkipVhdx
    BackupMode           = $BackupMode
    AutoResume           = -not [bool]$NoResume
    ResumeRunId          = $ResumeRunId
}

if ($Config.SkipVhdx) {
    if ($Config.BackupMode -eq "Vhdx") {
        throw "Use -BackupMode Vhdx sem -SkipVhdx, ou use -BackupMode Distros para copiar somente distros."
    }

    $Config.BackupMode = "Distros"
}

if ($NoResume.IsPresent -and -not [string]::IsNullOrWhiteSpace($ResumeRunId)) {
    throw "Use -NoResume ou -ResumeRunId, nao os dois ao mesmo tempo."
}

$script:RunId = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$script:RunStart = Get-Date
$script:LogFile = $null
$script:LockStream = $null
$script:LockFile = $null

function Write-Status {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "OK", "WARN", "ERROR", "TITLE")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    $color = @{
        INFO  = "Gray"
        OK    = "Green"
        WARN  = "Yellow"
        ERROR = "Red"
        TITLE = "Cyan"
    }[$Level]

    Write-Host $line -ForegroundColor $color

    if ($script:LogFile -and (Test-Path -LiteralPath $script:LogFile)) {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    }
}

function Write-Section {
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    $lines = @(
        "",
        "============================================================",
        " $Title",
        "============================================================"
    )

    Write-Host ""
    Write-Host $lines[1] -ForegroundColor Cyan
    Write-Host $lines[2] -ForegroundColor Cyan
    Write-Host $lines[3] -ForegroundColor Cyan

    if ($script:LogFile -and (Test-Path -LiteralPath $script:LogFile)) {
        Add-Content -LiteralPath $script:LogFile -Value $lines -Encoding UTF8
    }
}

function Format-Size {
    param(
        [Parameter(Mandatory)]
        [Int64]$Bytes
    )

    if ($Bytes -ge 1TB) { return ("{0:N2} TB" -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return ("{0} B" -f $Bytes)
}

function Get-ShortHash {
    param(
        [AllowNull()]
        [string]$Hash
    )

    if ([string]::IsNullOrWhiteSpace($Hash)) {
        return "N/A"
    }

    if ($Hash.Length -le 16) {
        return $Hash
    }

    return $Hash.Substring(0, 16) + "..."
}

function Assert-Command {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Comando obrigatorio nao encontrado: $Name"
    }
}

function Get-DriveInfoSafe {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)

    if ([string]::IsNullOrWhiteSpace($root) -or $root.StartsWith("\\")) {
        throw "O destino precisa estar em uma unidade local. Caminho recebido: $Path"
    }

    $driveLetter = $root.TrimEnd([char]'\')
    $drive = Get-CimInstance `
        -ClassName Win32_LogicalDisk `
        -Filter "DeviceID='$driveLetter'" `
        -ErrorAction Stop

    if (-not $drive) {
        throw "Unidade de destino nao encontrada: $driveLetter"
    }

    return [PSCustomObject]@{
        DeviceID   = $drive.DeviceID
        Label      = $drive.VolumeName
        FileSystem = $drive.FileSystem
        SizeBytes  = [Int64]$drive.Size
        FreeBytes  = [Int64]$drive.FreeSpace
    }
}

function Test-WriteAccess {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $testFile = Join-Path $Path ".write_test_$([guid]::NewGuid().ToString('N')).tmp"

    try {
        [System.IO.File]::WriteAllText($testFile, "WSL Backup Test")
        Remove-Item -LiteralPath $testFile -Force
    }
    catch {
        throw "Sem permissao de escrita no destino: $Path"
    }
}

function Assert-FreeSpace {
    param(
        [Parameter(Mandatory)]
        [string]$BackupRoot,

        [Parameter(Mandatory)]
        [Int64]$MinimumBytes,

        [Parameter(Mandatory)]
        [string]$Context
    )

    $driveInfo = Get-DriveInfoSafe -Path $BackupRoot

    if ($driveInfo.FreeBytes -lt $MinimumBytes) {
        throw (
            "Espaco insuficiente para: $Context. " +
            "Livre: $(Format-Size $driveInfo.FreeBytes). " +
            "Necessario: $(Format-Size $MinimumBytes)."
        )
    }

    Write-Status -Level "OK" -Message (
        "Espaco validado para ${Context}: " +
        "$(Format-Size $driveInfo.FreeBytes) livres."
    )
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory)]
        [string]$Parent,

        [Parameter(Mandatory)]
        [string]$Child
    )

    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd([char]'\') + "\"
    $childFull = [System.IO.Path]::GetFullPath($Child)

    if (-not $childFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Caminho fora da pasta esperada. Parent: $parentFull Child: $childFull"
    }
}

function Acquire-BackupLock {
    param(
        [Parameter(Mandatory)]
        [string]$BackupRoot
    )

    $script:LockFile = Join-Path $BackupRoot ".backup.lock"

    try {
        $script:LockStream = [System.IO.File]::Open(
            $script:LockFile,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )

        $lockText = @"
WSL Backup Lock
RunId: $script:RunId
Computer: $env:COMPUTERNAME
User: $env:USERNAME
Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($lockText)
        $script:LockStream.SetLength(0)
        $script:LockStream.Write($bytes, 0, $bytes.Length)
        $script:LockStream.Flush()

        Write-Status -Level "OK" -Message "Lock adquirido."
    }
    catch {
        throw "Ja existe outro backup em execucao ou o lock esta bloqueado: $script:LockFile. Detalhe: $($_.Exception.Message)"
    }
}

function Release-BackupLock {
    if ($script:LockStream) {
        $script:LockStream.Dispose()
        $script:LockStream = $null
    }

    if ($script:LockFile -and (Test-Path -LiteralPath $script:LockFile)) {
        Remove-Item -LiteralPath $script:LockFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-SafeFileName {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $safe = $Name -replace '[\\/:*?"<>|]', "_"
    $safe = $safe.Trim().TrimEnd([char]'.')

    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "unnamed_distro"
    }

    return $safe
}

function Get-FileHashSafe {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Label
    )

    Write-Status -Level "INFO" -Message "Calculando $($Config.HashAlgorithm): $Label"

    return (Get-FileHash `
        -LiteralPath $Path `
        -Algorithm $Config.HashAlgorithm `
        -ErrorAction Stop).Hash
}

function Test-TarArchive {
    param(
        [Parameter(Mandatory)]
        [string]$TarPath
    )

    $file = Get-Item -LiteralPath $TarPath -ErrorAction Stop

    if ($file.Length -lt 1KB) {
        throw "Arquivo TAR vazio ou invalido: $TarPath"
    }

    Write-Status -Level "INFO" -Message "Validando estrutura TAR: $($file.Name)"

    & tar.exe -tf $TarPath 1>$null 2>$null

    if ($LASTEXITCODE -ne 0) {
        throw "O arquivo TAR nao passou na validacao: $TarPath"
    }
}

function Stop-Wsl {
    Write-Status -Level "INFO" -Message "Desligando WSL para garantir consistencia..."

    & wsl.exe --shutdown

    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao desligar o WSL."
    }

    Start-Sleep -Seconds 3
    Write-Status -Level "OK" -Message "WSL desligado com sucesso."
}

function Get-WslDistros {
    Write-Status -Level "INFO" -Message "Lendo distribuicoes WSL instaladas..."

    $rawDistros = & wsl.exe --list --quiet 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao listar distribuicoes WSL."
    }

    $distros = @(
        $rawDistros |
            ForEach-Object {
                ([string]$_).Replace([string][char]0, "").Trim()
            } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            } |
            Select-Object -Unique
    )

    if ($distros.Count -eq 0) {
        throw "Nenhuma distribuicao WSL foi encontrada."
    }

    return $distros
}

function Get-WslDistroRegistryInfo {
    $baseKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss"

    if (-not (Test-Path -LiteralPath $baseKey)) {
        return @()
    }

    $items = @(
        Get-ChildItem -LiteralPath $baseKey |
            ForEach-Object {
                $props = Get-ItemProperty -Path $_.PSPath
                $nameProperty = $props.PSObject.Properties["DistributionName"]

                if ($nameProperty -and -not [string]::IsNullOrWhiteSpace([string]$nameProperty.Value)) {
                    $basePathProperty = $props.PSObject.Properties["BasePath"]
                    $basePath = ""

                    if ($basePathProperty) {
                        $basePath = [Environment]::ExpandEnvironmentVariables([string]$basePathProperty.Value)
                    }

                    $vhdPath = ""
                    $vhdBytes = [Int64]0

                    if (-not [string]::IsNullOrWhiteSpace($basePath)) {
                        $vhdPath = $basePath.TrimEnd([char]'\') + "\ext4.vhdx"

                        if (Test-Path -LiteralPath $vhdPath) {
                            $vhdBytes = [Int64](Get-Item -LiteralPath $vhdPath).Length
                        }
                    }

                    [PSCustomObject]@{
                        Name      = [string]$nameProperty.Value
                        BasePath  = $basePath
                        VhdxPath  = $vhdPath
                        VhdxBytes = $vhdBytes
                    }
                }
            }
    )

    return $items
}

function Test-IsDockerDistro {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    return ($Name -match "^(docker-desktop|docker-desktop-data)$")
}

function Get-BackupPlan {
    param(
        [Parameter(Mandatory)]
        [array]$DistroNames
    )

    $registryInfo = @(Get-WslDistroRegistryInfo)

    $plan = foreach ($name in $DistroNames) {
        $reg = $registryInfo |
            Where-Object { $_.Name -eq $name } |
            Select-Object -First 1

        $isDocker = Test-IsDockerDistro -Name $name
        $included = -not ($isDocker -and -not $Config.IncludeDocker)
        $reason = if ($included) { "Included" } else { "SkippedDocker" }

        $basePath = ""
        $vhdxPath = ""
        $vhdxBytes = [Int64]0

        if ($reg) {
            $basePath = [string]$reg.BasePath
            $vhdxPath = [string]$reg.VhdxPath
            $vhdxBytes = [Int64]$reg.VhdxBytes
        }

        [PSCustomObject]@{
            Name              = [string]$name
            SafeName          = Get-SafeFileName -Name ([string]$name)
            Included          = [bool]$included
            Reason            = $reason
            IsDocker          = [bool]$isDocker
            BasePath          = $basePath
            SourceVhdx        = $vhdxPath
            SourceVhdxBytes   = $vhdxBytes
            SourceVhdxSize    = Format-Size $vhdxBytes
        }
    }

    return @($plan)
}

function Get-BackupEstimate {
    param(
        [array]$SelectedDistros,

        [AllowNull()]
        [System.IO.FileInfo]$ExtraVhdxInfo
    )

    $distroBytes = [Int64]0
    foreach ($distro in $SelectedDistros) {
        $distroBytes += [Int64]$distro.SourceVhdxBytes
    }

    $extraBytes = [Int64]0
    if ($null -ne $ExtraVhdxInfo) {
        $extraBytes = [Int64]$ExtraVhdxInfo.Length
    }

    $reserveBytes = [Int64]($Config.MinimumFreeSpaceGB * 1GB)
    $totalBytes = [Int64]($distroBytes + $extraBytes + $reserveBytes)

    return [PSCustomObject]@{
        DistroBytes      = $distroBytes
        ExtraVhdxBytes   = $extraBytes
        ReserveBytes     = $reserveBytes
        TotalBytes       = $totalBytes
        DistroSize       = Format-Size $distroBytes
        ExtraVhdxSize    = Format-Size $extraBytes
        ReserveSize      = Format-Size $reserveBytes
        TotalSize        = Format-Size $totalBytes
    }
}

function New-DistroBackupResult {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Distro,

        [Parameter(Mandatory)]
        [string]$TarPath,

        [Parameter(Mandatory)]
        [string]$Hash,

        [Parameter(Mandatory)]
        [double]$DurationSeconds,

        [Parameter(Mandatory)]
        [string]$Status
    )

    $fileInfo = Get-Item -LiteralPath $TarPath -ErrorAction Stop

    return [PSCustomObject]@{
        Name                  = $Distro.Name
        File                  = "distros\$($Distro.SafeName).tar"
        SizeBytes             = [Int64]$fileInfo.Length
        SizeFormatted         = Format-Size $fileInfo.Length
        DurationSeconds       = [math]::Round($DurationSeconds, 1)
        SHA256                = $Hash
        SourceBasePath        = $Distro.BasePath
        SourceVhdx            = $Distro.SourceVhdx
        SourceVhdxBytes       = [Int64]$Distro.SourceVhdxBytes
        SourceVhdxSize        = $Distro.SourceVhdxSize
        Status                = $Status
    }
}

function Export-WslDistro {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Distro,

        [Parameter(Mandatory)]
        [string]$StageRoot
    )

    $start = Get-Date
    $distrosDir = Join-Path $StageRoot "distros"

    if (-not (Test-Path -LiteralPath $distrosDir)) {
        New-Item -ItemType Directory -Path $distrosDir -Force | Out-Null
    }

    $finalTar = Join-Path $distrosDir "$($Distro.SafeName).tar"
    $partialTar = "$finalTar.partial"

    if (Test-Path -LiteralPath $finalTar) {
        $startReuse = Get-Date
        Write-Status -Level "WARN" -Message "Reaproveitando TAR ja existente no staging: $($Distro.Name)"

        Test-TarArchive -TarPath $finalTar

        $hash = Get-FileHashSafe -Path $finalTar -Label "$($Distro.Name) existente"
        $duration = (Get-Date) - $startReuse
        $fileInfo = Get-Item -LiteralPath $finalTar

        Write-Status -Level "OK" -Message (
            "Distro reaproveitada: $($Distro.Name) | " +
            "Tamanho: $(Format-Size $fileInfo.Length) | " +
            "Hash: $(Get-ShortHash $hash)"
        )

        return New-DistroBackupResult `
            -Distro $Distro `
            -TarPath $finalTar `
            -Hash $hash `
            -DurationSeconds $duration.TotalSeconds `
            -Status "REUSED"
    }

    if (Test-Path -LiteralPath $partialTar) {
        Remove-Item -LiteralPath $partialTar -Force
    }

    Write-Status -Level "INFO" -Message "Exportando distro: $($Distro.Name)"

    $exportOutput = & wsl.exe --export $Distro.Name $partialTar 2>&1
    $exportExitCode = $LASTEXITCODE

    foreach ($line in @($exportOutput)) {
        $cleanLine = ([string]$line).Replace([string][char]0, "").Trim()

        if (-not [string]::IsNullOrWhiteSpace($cleanLine)) {
            Write-Status -Level "INFO" -Message "wsl export: $cleanLine"
        }
    }

    if ($exportExitCode -ne 0) {
        if (Test-Path -LiteralPath $partialTar) {
            Remove-Item -LiteralPath $partialTar -Force -ErrorAction SilentlyContinue
        }

        throw "Falha ao exportar a distro: $($Distro.Name)"
    }

    if (-not (Test-Path -LiteralPath $partialTar)) {
        throw "O arquivo TAR temporario nao foi criado: $($Distro.Name)"
    }

    Test-TarArchive -TarPath $partialTar

    $hash = Get-FileHashSafe -Path $partialTar -Label $Distro.Name

    Move-Item -LiteralPath $partialTar -Destination $finalTar
    $fileInfo = Get-Item -LiteralPath $finalTar

    $duration = (Get-Date) - $start

    Write-Status -Level "OK" -Message (
        "Distro concluida: $($Distro.Name) | " +
        "Tamanho: $(Format-Size $fileInfo.Length) | " +
        "Tempo: $([math]::Round($duration.TotalSeconds, 1)) s | " +
        "Hash: $(Get-ShortHash $hash)"
    )

    return New-DistroBackupResult `
        -Distro $Distro `
        -TarPath $finalTar `
        -Hash $hash `
        -DurationSeconds $duration.TotalSeconds `
        -Status "OK"
}

function Backup-Vhdx {
    param(
        [Parameter(Mandatory)]
        [string]$SourceVhdx,

        [Parameter(Mandatory)]
        [string]$StageRoot,

        [Parameter(Mandatory)]
        [string]$BackupRoot
    )

    if (-not (Test-Path -LiteralPath $SourceVhdx)) {
        throw "VHDX de origem nao localizado: $SourceVhdx"
    }

    $sourceInfo = Get-Item -LiteralPath $SourceVhdx

    if ($sourceInfo.Length -lt 1MB) {
        throw "VHDX parece invalido ou pequeno demais: $SourceVhdx"
    }

    $minimumFree = [Int64]($sourceInfo.Length + ($Config.MinimumFreeSpaceGB * 1GB))

    Assert-FreeSpace `
        -BackupRoot $BackupRoot `
        -MinimumBytes $minimumFree `
        -Context "copia segura do VHDX extra"

    $start = Get-Date
    $workspaceDir = Join-Path $StageRoot "workspace"

    if (-not (Test-Path -LiteralPath $workspaceDir)) {
        New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null
    }

    $sourceDir = Split-Path -Parent $SourceVhdx
    $sourceFile = Split-Path -Leaf $SourceVhdx
    $targetVhdx = Join-Path $workspaceDir $sourceFile

    Write-Status -Level "INFO" -Message (
        "Calculando hash do VHDX original: " +
        "$(Format-Size $sourceInfo.Length)"
    )

    $sourceHash = Get-FileHashSafe `
        -Path $SourceVhdx `
        -Label "VHDX original"

    if (Test-Path -LiteralPath $targetVhdx) {
        $existingInfo = Get-Item -LiteralPath $targetVhdx

        if ($existingInfo.Length -eq $sourceInfo.Length) {
            Write-Status -Level "WARN" -Message "Reaproveitando VHDX ja existente no staging: $targetVhdx"

            $existingHash = Get-FileHashSafe `
                -Path $targetVhdx `
                -Label "VHDX copiado existente"

            if ($sourceHash -eq $existingHash) {
                $duration = (Get-Date) - $start

                Write-Status -Level "OK" -Message (
                    "VHDX reaproveitado | " +
                    "Tamanho: $(Format-Size $existingInfo.Length) | " +
                    "Hash: $(Get-ShortHash $existingHash)"
                )

                return [PSCustomObject]@{
                    File            = "workspace\$sourceFile"
                    Source          = $SourceVhdx
                    SizeBytes       = [Int64]$existingInfo.Length
                    SizeFormatted   = Format-Size $existingInfo.Length
                    DurationSeconds = [math]::Round($duration.TotalSeconds, 1)
                    SHA256          = $existingHash
                    Status          = "REUSED"
                }
            }
        }

        Write-Status -Level "WARN" -Message "VHDX existente no staging nao confere com a origem. Copiando novamente."
        Remove-Item -LiteralPath $targetVhdx -Force
    }

    Write-Status -Level "INFO" -Message "Copiando VHDX com Robocopy..."

    & robocopy.exe `
        $sourceDir `
        $workspaceDir `
        $sourceFile `
        /J `
        /R:2 `
        /W:5 `
        /COPY:DAT `
        /DCOPY:T `
        /NP `
        /NFL `
        /NDL `
        /NJH `
        /NJS | Out-Null

    $robocopyCode = $LASTEXITCODE

    if ($robocopyCode -ge 8) {
        throw "Robocopy falhou ao copiar o VHDX. Codigo: $robocopyCode"
    }

    if (-not (Test-Path -LiteralPath $targetVhdx)) {
        throw "O VHDX de destino nao foi criado."
    }

    $targetInfo = Get-Item -LiteralPath $targetVhdx

    if ($sourceInfo.Length -ne $targetInfo.Length) {
        throw (
            "O tamanho do VHDX nao confere. " +
            "Origem: $(Format-Size $sourceInfo.Length). " +
            "Destino: $(Format-Size $targetInfo.Length)."
        )
    }

    $targetHash = Get-FileHashSafe `
        -Path $targetVhdx `
        -Label "VHDX copiado"

    if ($sourceHash -ne $targetHash) {
        throw "Falha critica: SHA-256 do VHDX copiado nao confere com o original."
    }

    $duration = (Get-Date) - $start

    Write-Status -Level "OK" -Message (
        "VHDX concluido | " +
        "Tamanho: $(Format-Size $targetInfo.Length) | " +
        "Tempo: $([math]::Round($duration.TotalSeconds, 1)) s | " +
        "Hash: $(Get-ShortHash $targetHash)"
    )

    return [PSCustomObject]@{
        File            = "workspace\$sourceFile"
        Source          = $SourceVhdx
        SizeBytes       = [Int64]$targetInfo.Length
        SizeFormatted   = Format-Size $targetInfo.Length
        DurationSeconds = [math]::Round($duration.TotalSeconds, 1)
        SHA256          = $targetHash
        Status          = "OK"
    }
}

function Write-Checksums {
    param(
        [Parameter(Mandatory)]
        [string]$StageRoot,

        [array]$Distros,

        [AllowNull()]
        [PSCustomObject]$Vhdx
    )

    $path = Join-Path $StageRoot "checksums.sha256"
    $lines = @(
        "# SHA-256 checksums",
        "# Run ID: $script:RunId",
        "# Criado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        ""
    )

    foreach ($distro in $Distros) {
        if (-not $distro.PSObject.Properties["SHA256"]) {
            throw "Resultado de distro invalido ao gerar checksums. Valor recebido: $distro"
        }

        $lines += "$($distro.SHA256) *$($distro.File)"
    }

    if ($null -ne $Vhdx) {
        if (-not $Vhdx.PSObject.Properties["SHA256"]) {
            throw "Resultado de VHDX invalido ao gerar checksums. Valor recebido: $Vhdx"
        }

        $lines += "$($Vhdx.SHA256) *$($Vhdx.File)"
    }

    Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
}

function Write-RestoreGuide {
    param(
        [Parameter(Mandatory)]
        [string]$StageRoot,

        [Parameter(Mandatory)]
        [string]$FinalRunPath,

        [array]$Distros,

        [AllowNull()]
        [PSCustomObject]$Vhdx
    )

    $path = Join-Path $StageRoot "RESTORE_GUIDE.txt"
    $lines = @(
        "GUIA DE RESTAURACAO WSL",
        "Run ID: $script:RunId",
        "Criado em: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "",
        "ANTES DE RESTAURAR:",
        "1. Execute: wsl.exe --shutdown",
        "2. Confira os hashes em checksums.sha256.",
        "3. Nao importe uma distro com nome ja existente.",
        "",
        "COMANDOS PARA RESTAURAR AS DISTROS:"
    )

    if ($Distros.Count -eq 0) {
        $lines += ""
        $lines += "Nenhuma distro foi incluida neste backup."
    }
    else {
        foreach ($distro in $Distros) {
            $targetName = Get-SafeFileName -Name $distro.Name
            $targetPath = "D:\WSL-Restored\$targetName"
            $tarPath = Join-Path $FinalRunPath $distro.File

            $lines += ""
            $lines += (
                "wsl.exe --import `"$($distro.Name)`" " +
                "`"$targetPath`" " +
                "`"$tarPath`" --version 2"
            )
        }
    }

    $lines += ""
    $lines += "VHDX EXTRA:"

    if ($null -ne $Vhdx) {
        $lines += "Restaure este arquivo somente com o WSL desligado."
        $lines += "Arquivo: $(Join-Path $FinalRunPath $Vhdx.File)"
    }
    else {
        $lines += "Nao incluido nesta execucao."
    }

    Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
}

function Write-Manifest {
    param(
        [Parameter(Mandatory)]
        [string]$StageRoot,

        [Parameter(Mandatory)]
        [string]$FinalRunPath,

        [Parameter(Mandatory)]
        [PSCustomObject]$DriveInfo,

        [array]$Distros,

        [array]$SkippedDistros,

        [Parameter(Mandatory)]
        [PSCustomObject]$Estimate,

        [AllowNull()]
        [PSCustomObject]$Vhdx
    )

    $duration = (Get-Date) - $script:RunStart

    $manifest = [ordered]@{
        SchemaVersion = "1.1"
        RunId         = $script:RunId
        StartedAt     = $script:RunStart.ToString("yyyy-MM-dd HH:mm:ss")
        CompletedAt   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        DurationSec   = [math]::Round($duration.TotalSeconds, 1)

        Computer = @{
            Name              = $env:COMPUTERNAME
            User              = $env:USERNAME
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        }

        Destination = @{
            Root       = $Config.BackupRoot
            RunPath    = $FinalRunPath
            Drive      = $DriveInfo.DeviceID
            Label      = $DriveInfo.Label
            FileSystem = $DriveInfo.FileSystem
        }

        Options = @{
            BackupMode        = $Config.BackupMode
            HashAlgorithm     = $Config.HashAlgorithm
            IncludeDocker     = $Config.IncludeDocker
            SkipVhdx          = $Config.SkipVhdx
            AutoResume        = $Config.AutoResume
            SourceVhdx        = $Config.SourceVhdx
            KeepLastRuns      = $Config.KeepLastRuns
            MinimumFreeGB     = $Config.MinimumFreeSpaceGB
        }

        Estimate       = $Estimate
        Distros        = $Distros
        SkippedDistros = $SkippedDistros
        Vhdx           = $Vhdx
    }

    $manifest |
        ConvertTo-Json -Depth 10 |
        Set-Content `
            -LiteralPath (Join-Path $StageRoot "manifest.json") `
            -Encoding UTF8
}

function Update-Latest {
    param(
        [Parameter(Mandatory)]
        [string]$BackupRoot,

        [Parameter(Mandatory)]
        [string]$FinalRunPath
    )

    $latestPath = Join-Path $BackupRoot "LATEST.txt"

    @"
Ultimo backup WSL concluido com sucesso

Run ID: $script:RunId
Data: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Pasta: $FinalRunPath
"@ | Set-Content -LiteralPath $latestPath -Encoding UTF8
}

function Remove-OldBackups {
    param(
        [Parameter(Mandatory)]
        [string]$RunsRoot
    )

    $runs = @(
        Get-ChildItem -LiteralPath $RunsRoot -Directory |
            Where-Object { $_.Name -match "^\d{8}_\d{6}_\d{3}$" } |
            Sort-Object LastWriteTime -Descending
    )

    if ($runs.Count -le $Config.KeepLastRuns) {
        Write-Status -Level "INFO" -Message (
            "Retencao: $($runs.Count) backup(s) existente(s). " +
            "Nada para remover."
        )

        return
    }

    $oldRuns = $runs | Select-Object -Skip $Config.KeepLastRuns

    foreach ($run in $oldRuns) {
        Assert-ChildPath -Parent $RunsRoot -Child $run.FullName

        Write-Status -Level "WARN" -Message "Removendo backup antigo: $($run.FullName)"

        Remove-Item `
            -LiteralPath $run.FullName `
            -Recurse `
            -Force

        Write-Status -Level "OK" -Message "Backup antigo removido: $($run.Name)"
    }
}

function Get-StageRunId {
    param(
        [Parameter(Mandatory)]
        [string]$StageRoot
    )

    $name = Split-Path -Leaf $StageRoot
    return ($name -replace "\.partial$", "")
}

function Get-StageBackupMode {
    param(
        [Parameter(Mandatory)]
        [string]$StageRoot
    )

    $statePath = Join-Path $StageRoot "resume_state.json"

    if (Test-Path -LiteralPath $statePath) {
        try {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

            if ($state.BackupMode -in @("All", "Distros", "Vhdx")) {
                return [string]$state.BackupMode
            }
        }
        catch {
            Write-Status -Level "WARN" -Message "Nao foi possivel ler resume_state.json em $StageRoot."
        }
    }

    # Stagings antigos, criados antes do modo selecionavel, eram sempre All.
    return "All"
}

function Find-ResumeStage {
    param(
        [Parameter(Mandatory)]
        [string]$StagingRoot,

        [Parameter(Mandatory)]
        [string]$BackupMode,

        [AllowNull()]
        [string]$ResumeRunId
    )

    if (-not [string]::IsNullOrWhiteSpace($ResumeRunId)) {
        $explicitStage = Join-Path $StagingRoot "$ResumeRunId.partial"

        if (-not (Test-Path -LiteralPath $explicitStage -PathType Container)) {
            throw "Staging solicitado para retomada nao encontrado: $explicitStage"
        }

        return $explicitStage
    }

    $candidates = @(
        Get-ChildItem -LiteralPath $StagingRoot -Directory -Filter "*.partial" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )

    foreach ($candidate in $candidates) {
        $stageMode = Get-StageBackupMode -StageRoot $candidate.FullName

        if ($stageMode -eq $BackupMode) {
            return $candidate.FullName
        }
    }

    return $null
}

function Write-ResumeState {
    param(
        [Parameter(Mandatory)]
        [string]$StageRoot,

        [array]$SelectedDistros,

        [Parameter(Mandatory)]
        [bool]$WillBackupExtraVhdx
    )

    $state = [ordered]@{
        RunId               = $script:RunId
        BackupMode          = $Config.BackupMode
        UpdatedAt           = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        IncludeDocker       = $Config.IncludeDocker
        WillBackupExtraVhdx = $WillBackupExtraVhdx
        SourceVhdx          = $Config.SourceVhdx
        SelectedDistros     = @($SelectedDistros | Select-Object -ExpandProperty Name)
    }

    $state |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $StageRoot "resume_state.json") -Encoding UTF8
}

function New-LogFilePath {
    param(
        [Parameter(Mandatory)]
        [string]$LogsRoot
    )

    $path = Join-Path $LogsRoot "Mega_Backup_WSL_$script:RunId.log"

    if (-not (Test-Path -LiteralPath $path)) {
        return $path
    }

    $suffix = Get-Date -Format "yyyyMMdd_HHmmss"
    return (Join-Path $LogsRoot "Mega_Backup_WSL_$($script:RunId)_resume_$suffix.log")
}

$stageRoot = $null
$finalRunPath = $null
$backupCompleted = $false
$resumingExistingStage = $false

try {
    Write-Section "MEGA BACKUP WSL - SEGURO E VERSIONADO"

    $needsDistros = ($Config.BackupMode -in @("All", "Distros"))
    $needsExtraVhdx = ($Config.BackupMode -in @("All", "Vhdx"))

    Assert-Command -Name "wsl.exe"

    if ($needsDistros) {
        Assert-Command -Name "tar.exe"
    }

    if ($needsExtraVhdx) {
        Assert-Command -Name "robocopy.exe"
    }

    if ([string]::IsNullOrWhiteSpace($Config.BackupRoot)) {
        throw "BackupRoot nao pode ficar vazio."
    }

    $backupRoot = [System.IO.Path]::GetFullPath($Config.BackupRoot)
    $sourceVhdxFull = $null

    if (-not [string]::IsNullOrWhiteSpace($Config.SourceVhdx)) {
        $sourceVhdxFull = [System.IO.Path]::GetFullPath($Config.SourceVhdx)
    }

    if (-not (Test-Path -LiteralPath $backupRoot)) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    }

    $driveInfo = Get-DriveInfoSafe -Path $backupRoot

    if (
        -not [string]::IsNullOrWhiteSpace($Config.ExpectedVolumeLabel) -and
        $driveInfo.Label -ne $Config.ExpectedVolumeLabel
    ) {
        throw (
            "Rotulo da unidade incorreto. " +
            "Esperado: '$($Config.ExpectedVolumeLabel)'. " +
            "Atual: '$($driveInfo.Label)'."
        )
    }

    Test-WriteAccess -Path $backupRoot

    $runsRoot = Join-Path $backupRoot "Runs"
    $stagingRoot = Join-Path $backupRoot "_staging"
    $logsRoot = Join-Path $backupRoot "logs"

    foreach ($directory in @($runsRoot, $stagingRoot, $logsRoot)) {
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
    }

    if (-not $DryRun.IsPresent -and $Config.AutoResume) {
        $resumeStage = Find-ResumeStage `
            -StagingRoot $stagingRoot `
            -BackupMode $Config.BackupMode `
            -ResumeRunId $Config.ResumeRunId

        if ($resumeStage) {
            $stageRoot = $resumeStage
            $script:RunId = Get-StageRunId -StageRoot $stageRoot
            $finalRunPath = Join-Path $runsRoot $script:RunId
            $resumingExistingStage = $true
        }
    }

    $script:LogFile = New-LogFilePath -LogsRoot $logsRoot
    New-Item -ItemType File -Path $script:LogFile -Force | Out-Null

    Acquire-BackupLock -BackupRoot $backupRoot

    Write-Status -Level "TITLE" -Message "ID da execucao: $script:RunId"
    Write-Status -Level "INFO" -Message "Modo de backup: $($Config.BackupMode)"
    Write-Status -Level "INFO" -Message "Retomada automatica: $($Config.AutoResume)"
    if ($resumingExistingStage) {
        Write-Status -Level "WARN" -Message "Retomando staging existente: $stageRoot"
    }
    Write-Status -Level "INFO" -Message "Computador: $env:COMPUTERNAME"
    Write-Status -Level "INFO" -Message "Usuario: $env:USERNAME"
    Write-Status -Level "INFO" -Message "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Status -Level "INFO" -Message "Destino: $backupRoot"
    Write-Status -Level "INFO" -Message (
        "Unidade: $($driveInfo.DeviceID) | " +
        "Rotulo: $($driveInfo.Label) | " +
        "Formato: $($driveInfo.FileSystem)"
    )
    Write-Status -Level "INFO" -Message (
        "Espaco livre: $(Format-Size $driveInfo.FreeBytes) / " +
        "$(Format-Size $driveInfo.SizeBytes)"
    )
    Write-Status -Level "INFO" -Message "Docker incluido: $($Config.IncludeDocker)"
    Write-Status -Level "INFO" -Message "VHDX extra incluido: $needsExtraVhdx"
    Write-Status -Level "INFO" -Message "Log: $script:LogFile"

    Assert-FreeSpace `
        -BackupRoot $backupRoot `
        -MinimumBytes ([Int64]($Config.MinimumFreeSpaceGB * 1GB)) `
        -Context "inicio do backup"

    Write-Section "INVENTARIO"

    $backupPlan = @()
    $selectedDistros = @()
    $skippedDistros = @()

    if ($needsDistros) {
        $distroNames = Get-WslDistros
        $backupPlan = @(Get-BackupPlan -DistroNames $distroNames)
        $selectedDistros = @($backupPlan | Where-Object { $_.Included })
        $skippedDistros = @($backupPlan | Where-Object { -not $_.Included })

        if ($selectedDistros.Count -eq 0) {
            throw "Nenhuma distro foi selecionada para backup."
        }

        foreach ($distro in $selectedDistros) {
            Write-Status -Level "INFO" -Message (
                "Distro selecionada: $($distro.Name) | " +
                "VHDX estimado: $($distro.SourceVhdxSize)"
            )
        }

        foreach ($distro in $skippedDistros) {
            Write-Status -Level "WARN" -Message "Distro ignorada: $($distro.Name) ($($distro.Reason))"
        }
    }
    else {
        Write-Status -Level "WARN" -Message "Modo VHDX: inventario de distros ignorado."
    }

    if ($needsExtraVhdx -and [string]::IsNullOrWhiteSpace($sourceVhdxFull)) {
        throw "BackupMode $($Config.BackupMode) exige um caminho em -SourceVhdx."
    }

    $willBackupExtraVhdx = $needsExtraVhdx -and (-not [string]::IsNullOrWhiteSpace($sourceVhdxFull))
    $sourceVhdxInfo = $null

    if ($willBackupExtraVhdx) {
        if (-not (Test-Path -LiteralPath $sourceVhdxFull)) {
            throw "VHDX extra nao encontrado: $sourceVhdxFull. Use -BackupMode Distros para fazer backup somente das distros."
        }

        $sourceVhdxInfo = Get-Item -LiteralPath $sourceVhdxFull
        Write-Status -Level "INFO" -Message (
            "VHDX extra selecionado: $sourceVhdxFull | " +
            "Tamanho: $(Format-Size $sourceVhdxInfo.Length)"
        )
    }
    else {
        Write-Status -Level "WARN" -Message "VHDX extra nao sera incluido nesta execucao."
    }

    $unknownSizeDistros = @($selectedDistros | Where-Object { [Int64]$_.SourceVhdxBytes -le 0 })

    if ($unknownSizeDistros.Count -gt 0) {
        Write-Status -Level "WARN" -Message (
            "Nao foi possivel estimar o tamanho de: " +
            (($unknownSizeDistros | Select-Object -ExpandProperty Name) -join ", ")
        )
    }

    $estimate = Get-BackupEstimate `
        -SelectedDistros $selectedDistros `
        -ExtraVhdxInfo $sourceVhdxInfo

    Write-Status -Level "INFO" -Message (
        "Estimativa conservadora: distros $($estimate.DistroSize) + " +
        "VHDX extra $($estimate.ExtraVhdxSize) + " +
        "reserva $($estimate.ReserveSize) = $($estimate.TotalSize)"
    )

    Assert-FreeSpace `
        -BackupRoot $backupRoot `
        -MinimumBytes ([Int64]$estimate.TotalBytes) `
        -Context "backup completo estimado"

    if ($DryRun.IsPresent) {
        Write-Section "MODO TESTE"
        Write-Status -Level "WARN" -Message "DryRun ativo: nenhuma distro sera exportada e nenhum VHDX sera copiado."
        Write-Status -Level "OK" -Message "Pre-validacoes e inventario concluidos com sucesso."
        $backupCompleted = $true
    }
    else {
        if (-not $resumingExistingStage) {
            $stageRoot = Join-Path $stagingRoot "$script:RunId.partial"
            $finalRunPath = Join-Path $runsRoot $script:RunId

            if (Test-Path -LiteralPath $stageRoot) {
                throw "Staging ja existe: $stageRoot"
            }

            New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        }

        if (Test-Path -LiteralPath $finalRunPath) {
            throw "Destino final ja existe: $finalRunPath"
        }

        Write-ResumeState `
            -StageRoot $stageRoot `
            -SelectedDistros $selectedDistros `
            -WillBackupExtraVhdx $willBackupExtraVhdx

        Write-Section "ETAPA 1 DE 4 - DESLIGAR WSL"
        Stop-Wsl

        $distroResults = @()

        if ($needsDistros) {
            Write-Section "ETAPA 2 DE 4 - EXPORTAR DISTROS"

            foreach ($distro in $selectedDistros) {
                $result = Export-WslDistro `
                    -Distro $distro `
                    -StageRoot $stageRoot

                $distroResults += $result
            }
        }
        else {
            Write-Section "ETAPA 2 DE 4 - EXPORTAR DISTROS"
            Write-Status -Level "WARN" -Message "Etapa de distros ignorada pelo modo $($Config.BackupMode)."
        }

        if ($needsDistros -and $distroResults.Count -eq 0) {
            throw "Nenhuma distro foi exportada."
        }

        Write-Section "ETAPA 3 DE 4 - COPIAR VHDX EXTRA"

        $vhdxResult = $null

        if ($willBackupExtraVhdx) {
            $vhdxResult = Backup-Vhdx `
                -SourceVhdx $sourceVhdxFull `
                -StageRoot $stageRoot `
                -BackupRoot $backupRoot
        }
        else {
            Write-Status -Level "WARN" -Message "Etapa de VHDX extra ignorada."
        }

        if (-not $needsDistros -and $null -eq $vhdxResult) {
            throw "Nenhum item foi incluido no backup."
        }

        Write-Section "ETAPA 4 DE 4 - RELATORIOS E PUBLICACAO"

        Write-Checksums `
            -StageRoot $stageRoot `
            -Distros $distroResults `
            -Vhdx $vhdxResult

        Write-RestoreGuide `
            -StageRoot $stageRoot `
            -FinalRunPath $finalRunPath `
            -Distros $distroResults `
            -Vhdx $vhdxResult

        Write-Manifest `
            -StageRoot $stageRoot `
            -FinalRunPath $finalRunPath `
            -DriveInfo $driveInfo `
            -Distros $distroResults `
            -SkippedDistros $skippedDistros `
            -Estimate $estimate `
            -Vhdx $vhdxResult

        $failedReportPath = Join-Path $stageRoot "FAILED.json"
        if (Test-Path -LiteralPath $failedReportPath) {
            Remove-Item -LiteralPath $failedReportPath -Force
        }

        Move-Item `
            -LiteralPath $stageRoot `
            -Destination $finalRunPath

        Update-Latest `
            -BackupRoot $backupRoot `
            -FinalRunPath $finalRunPath

        $backupCompleted = $true

        Write-Status -Level "OK" -Message "Backup publicado em: $finalRunPath"

        try {
            Remove-OldBackups -RunsRoot $runsRoot
        }
        catch {
            Write-Status -Level "WARN" -Message "Retencao falhou, mas o backup novo foi concluido: $($_.Exception.Message)"
        }

        Write-Section "RESUMO"

        $distroResults |
            Select-Object `
                Name,
                SizeFormatted,
                DurationSeconds,
                @{Name = "SHA256"; Expression = { Get-ShortHash $_.SHA256 } } |
            Format-Table -AutoSize

        if ($null -ne $vhdxResult) {
            Write-Status -Level "OK" -Message (
                "VHDX extra: $($vhdxResult.SizeFormatted) | " +
                "SHA-256: $(Get-ShortHash $vhdxResult.SHA256)"
            )
        }
    }

    $duration = (Get-Date) - $script:RunStart

    Write-Section "CONCLUIDO"
    Write-Status -Level "OK" -Message "Tempo total: $([math]::Round($duration.TotalMinutes, 2)) minuto(s)."
    Write-Status -Level "OK" -Message "Log final: $script:LogFile"
}
catch {
    Write-Section "ERRO CRITICO"
    Write-Status -Level "ERROR" -Message $_.Exception.Message

    if ($stageRoot -and (Test-Path -LiteralPath $stageRoot)) {
        $failedReport = @{
            RunId      = $script:RunId
            FailedAt   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Computer   = $env:COMPUTERNAME
            User       = $env:USERNAME
            BackupMode = $Config.BackupMode
            StageRoot  = $stageRoot
            LogFile    = $script:LogFile
            Error      = $_.Exception.Message
        }

        $failedReport |
            ConvertTo-Json |
            Set-Content `
                -LiteralPath (Join-Path $stageRoot "FAILED.json") `
                -Encoding UTF8

        Write-Status -Level "WARN" -Message "Staging preservado para diagnostico: $stageRoot"
    }

    Write-Status -Level "WARN" -Message "Nenhum backup anterior foi apagado."
    exit 1
}
finally {
    Release-BackupLock
}

if ($backupCompleted) {
    exit 0
}

exit 1
