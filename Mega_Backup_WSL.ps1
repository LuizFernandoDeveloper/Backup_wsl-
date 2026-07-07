#requires -Version 5.1
<#
    MEGA BACKUP WSL

    Backup seguro, versionado e validado para distros WSL e, opcionalmente,
    um VHDX extra de laboratorio.

    Melhorias principais:
    - Parametros para destino, VHDX, retencao e reserva de espaco.
    - Modo -DryRun com inventario e estimativa, sem exportar nem copiar.
    - Modo -HealthOnly para diagnosticar as distros sem backup.
    - Diagnostico pesado opcional com -DeepHealth.
    - Escolha de modo: All, Distros ou Vhdx.
    - Retomada automatica de backup interrompido em _staging.
    - Limpeza opcional de sockets temporarios com -CleanWslSockets.
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

    [ValidateSet("Basic", "Standard", "Template")]
    [string]$QualityGate = "Standard",

    [switch]$IncludeDocker,
    [switch]$SkipVhdx,
    [switch]$CleanWslSockets,
    [switch]$PurifyOnly,
    [switch]$HealthOnly,
    [Alias("DiagnosticoPesado")]
    [switch]$DeepHealth,
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
    QualityGate          = $QualityGate
    CleanWslSockets      = [bool]$CleanWslSockets
    PurifyOnly           = [bool]$PurifyOnly
    HealthOnly           = [bool]$HealthOnly
    DeepHealth           = [bool]$DeepHealth
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

if ($Config.QualityGate -eq "Template") {
    $Config.DeepHealth = $true
}

if ($Config.PurifyOnly) {
    $Config.DeepHealth = $true
}

$script:RunId = Get-Date -Format "yyyyMMdd_HHmmss_fff"
$script:RunStart = Get-Date
$script:LogFile = $null
$script:LockStream = $null
$script:LockFile = $null

function ConvertTo-SafeLogText {
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    $text = [string]$Value
    $text = $text.Replace([string][char]0, "")
    $text = [regex]::Replace($text, '\x1B\[[0-?]*[ -/]*[@-~]', "")
    $text = [regex]::Replace($text, '[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]', " ")
    $text = $text.Replace("`r", " ").Replace("`n", " ")
    $text = [regex]::Replace($text, '\s{2,}', " ")

    return $text.Trim()
}

function Get-ConsoleLineWidth {
    try {
        $width = [int]$Host.UI.RawUI.WindowSize.Width
    }
    catch {
        $width = 120
    }

    if ($width -lt 80) {
        return 80
    }

    if ($width -gt 132) {
        return 132
    }

    return ($width - 1)
}

function Split-TextForConsole {
    param(
        [AllowNull()]
        [string]$Text,

        [Parameter(Mandatory)]
        [int]$Width
    )

    $safeText = ConvertTo-SafeLogText -Value $Text

    if ([string]::IsNullOrWhiteSpace($safeText)) {
        return @("")
    }

    if ($Width -lt 20) {
        $Width = 20
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $current = ""
    $words = $safeText -split ' '

    foreach ($word in $words) {
        if ([string]::IsNullOrWhiteSpace($word)) {
            continue
        }

        while ($word.Length -gt $Width) {
            if (-not [string]::IsNullOrWhiteSpace($current)) {
                $lines.Add($current)
                $current = ""
            }

            $lines.Add($word.Substring(0, $Width))
            $word = $word.Substring($Width)
        }

        if ([string]::IsNullOrWhiteSpace($current)) {
            $current = $word
        }
        elseif (($current.Length + 1 + $word.Length) -le $Width) {
            $current = "$current $word"
        }
        else {
            $lines.Add($current)
            $current = $word
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($current)) {
        $lines.Add($current)
    }

    if ($lines.Count -eq 0) {
        return @("")
    }

    return @($lines)
}

function Get-TextFileLines {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Oem
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    if ($Oem.IsPresent) {
        try {
            return @(Get-Content -LiteralPath $Path -Encoding Oem -ErrorAction Stop)
        }
        catch {
            return @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
        }
    }

    return @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
}

function Write-Status {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "OK", "WARN", "ERROR", "TITLE")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = "[$timestamp] [$Level]"
    $width = Get-ConsoleLineWidth
    $messageWidth = $width - $prefix.Length - 1

    if ($messageWidth -lt 40) {
        $messageWidth = 40
    }

    $messageLines = Split-TextForConsole -Text $Message -Width $messageWidth
    $color = @{
        INFO  = "Gray"
        OK    = "Green"
        WARN  = "Yellow"
        ERROR = "Red"
        TITLE = "Cyan"
    }[$Level]

    $lines = @()

    foreach ($messageLine in $messageLines) {
        $line = "$prefix $messageLine"
        $lines += $line
        Write-Host $line -ForegroundColor $color
    }

    if ($script:LogFile -and (Test-Path -LiteralPath $script:LogFile)) {
        Add-Content -LiteralPath $script:LogFile -Value $lines -Encoding UTF8
    }
}

function Write-Section {
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    $width = Get-ConsoleLineWidth
    if ($width -gt 76) {
        $width = 76
    }

    $safeTitle = ConvertTo-SafeLogText -Value $Title
    if ($safeTitle.Length -gt ($width - 1)) {
        $safeTitle = $safeTitle.Substring(0, [math]::Max(1, $width - 4)) + "..."
    }

    $bar = "=" * $width
    $lines = @(
        "",
        $bar,
        " $safeTitle",
        $bar
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

function Get-ManagedSha256Hash {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $stream = $null
    $sha256 = $null

    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )

        $bytes = $sha256.ComputeHash($stream)
        return ([System.BitConverter]::ToString($bytes) -replace "-", "").ToUpperInvariant()
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }

        if ($null -ne $sha256) {
            $sha256.Dispose()
        }
    }
}

function Get-FileHashSafe {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Label
    )

    Write-Status -Level "INFO" -Message "Calculando $($Config.HashAlgorithm): $Label"

    $hashCommand = Get-Command -Name "Get-FileHash" -CommandType Cmdlet,Function -ErrorAction SilentlyContinue

    if ($null -ne $hashCommand) {
        return (& $hashCommand `
            -LiteralPath $Path `
            -Algorithm $Config.HashAlgorithm `
            -ErrorAction Stop).Hash
    }

    if ($Config.HashAlgorithm -ne "SHA256") {
        throw "Get-FileHash indisponivel e fallback interno suporta apenas SHA256."
    }

    Write-Status -Level "WARN" -Message "Get-FileHash indisponivel; usando calculo SHA256 interno via .NET."
    return Get-ManagedSha256Hash -Path $Path
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

function ConvertTo-Int64Default {
    param(
        [AllowNull()]
        [object]$Value,

        [Int64]$Default = 0
    )

    $parsed = [Int64]0

    if ($null -ne $Value -and [Int64]::TryParse(([string]$Value).Trim(), [ref]$parsed)) {
        return $parsed
    }

    return $Default
}

function ConvertTo-PercentInt {
    param(
        [AllowNull()]
        [object]$Value
    )

    $clean = ([string]$Value).Trim().TrimEnd([char]'%')
    return [int](ConvertTo-Int64Default -Value $clean -Default 0)
}

function Convert-KeyValueLines {
    param(
        [array]$Lines
    )

    $map = @{}

    foreach ($line in @($Lines)) {
        $text = ([string]$line).Replace([string][char]0, "").Trim()

        if ($text -match "^([^=]+)=(.*)$") {
            $map[$Matches[1]] = $Matches[2]
        }
    }

    return $map
}

function Invoke-WslDistroCommand {
    param(
        [Parameter(Mandatory)]
        [string]$DistroName,

        [Parameter(Mandatory)]
        [string]$Command,

        [string]$User = ""
    )

    $id = [guid]::NewGuid().ToString("N")
    $stdoutPath = Join-Path $env:TEMP "wsl_backup_$id.stdout.log"
    $stderrPath = Join-Path $env:TEMP "wsl_backup_$id.stderr.log"
    $scriptPath = Join-Path $env:TEMP "wsl_backup_$id.sh"

    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($scriptPath, $Command, $utf8NoBom)

        $fullScriptPath = [System.IO.Path]::GetFullPath($scriptPath)
        $driveLetter = $fullScriptPath.Substring(0, 1).ToLowerInvariant()
        $pathRest = $fullScriptPath.Substring(2).Replace("\", "/")
        $wslScriptPath = "/mnt/$driveLetter$pathRest"

        try {
            if ([string]::IsNullOrWhiteSpace($User)) {
                & wsl.exe -d $DistroName -- sh $wslScriptPath 1>$stdoutPath 2>$stderrPath
            }
            else {
                & wsl.exe -d $DistroName -u $User -- sh $wslScriptPath 1>$stdoutPath 2>$stderrPath
            }

            $exitCode = $LASTEXITCODE
        }
        catch {
            $exitCode = 1
            Add-Content -LiteralPath $stderrPath -Value $_.Exception.Message -Encoding UTF8
        }

        return [PSCustomObject]@{
            ExitCode = [int]$exitCode
            Stdout   = @(Get-TextFileLines -Path $stdoutPath)
            Stderr   = @(Get-TextFileLines -Path $stderrPath)
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath, $scriptPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-WslDistroHealth {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Distro,

        [switch]$Deep
    )

    $command = @'
root_df=$(df -P / 2>/dev/null | awk 'NR==2 {print $2 "|" $3 "|" $4 "|" $5}')
inode_df=$(df -Pi / 2>/dev/null | awk 'NR==2 {print $2 "|" $3 "|" $4 "|" $5}')
tmp_sockets=$(find /tmp -xdev -type s 2>/dev/null | wc -l | tr -d " ")
var_tmp_sockets=$(find /var/tmp -xdev -type s 2>/dev/null | wc -l | tr -d " ")
ssh_sockets=$(find "$HOME/.ssh/agent" -type s 2>/dev/null | wc -l | tr -d " ")
printf 'ROOT_DF=%s\n' "$root_df"
printf 'INODE_DF=%s\n' "$inode_df"
printf 'TMP_SOCKETS=%s\n' "${tmp_sockets:-0}"
printf 'VAR_TMP_SOCKETS=%s\n' "${var_tmp_sockets:-0}"
printf 'SSH_AGENT_SOCKETS=%s\n' "${ssh_sockets:-0}"
'@

    if ($Deep.IsPresent) {
        $command += @'
all_sockets=$(find / -xdev -type s 2>/dev/null | wc -l | tr -d " ")
broken_links=$(find / -xdev -xtype l 2>/dev/null | wc -l | tr -d " ")
cache_sizes=$(du -xsk /tmp /var/tmp /var/cache "$HOME/.cache" 2>/dev/null | awk '{printf "%s:%s,", $2, $1}')
top_root_dirs=$(du -xk --max-depth=1 / 2>/dev/null | sort -nr | head -8 | awk '{printf "%s:%s,", $2, $1}')
root_options=$(findmnt -no OPTIONS / 2>/dev/null || mount | awk '$3=="/"{print $6; exit}')
case ",$root_options," in
  *,ro,*|*\(ro,*|*,ro\)*) root_readonly=1 ;;
  *) root_readonly=0 ;;
esac
tmp_writable=0
tmp_probe=$(mktemp /tmp/wsl-backup-health.XXXXXX 2>/dev/null)
if [ -n "$tmp_probe" ] && printf test > "$tmp_probe" 2>/dev/null; then
  tmp_writable=1
  rm -f "$tmp_probe" 2>/dev/null
fi
home_writable=0
home_probe="$HOME/.wsl-backup-health.$$"
if printf test > "$home_probe" 2>/dev/null; then
  home_writable=1
  rm -f "$home_probe" 2>/dev/null
fi
find_errors=$(find / -xdev -type d -print >/dev/null 2>&1 | grep -Eiv 'Permission denied|Operation not permitted' | head -20 | sed 's/|/ /g' | tr '\n' '|')
find_error_count=$(find / -xdev -type d -print >/dev/null 2>&1 | grep -Eiv 'Permission denied|Operation not permitted' | wc -l | tr -d " ")
dmesg_issues=$(dmesg 2>/dev/null | grep -Ei 'EXT4-fs error|EXT4-fs warning|I/O error|Buffer I/O error|blk_update_request|read-only file system|Structure needs cleaning|metadata_csum|orphan linked list' | tail -20 | sed 's/|/ /g' | tr '\n' '|')
printf 'ALL_SOCKETS=%s\n' "${all_sockets:-0}"
printf 'BROKEN_LINKS=%s\n' "${broken_links:-0}"
printf 'CACHE_SIZES=%s\n' "$cache_sizes"
printf 'TOP_ROOT_DIRS=%s\n' "$top_root_dirs"
printf 'ROOT_OPTIONS=%s\n' "$root_options"
printf 'ROOT_READONLY=%s\n' "$root_readonly"
printf 'TMP_WRITABLE=%s\n' "$tmp_writable"
printf 'HOME_WRITABLE=%s\n' "$home_writable"
printf 'FIND_ERROR_COUNT=%s\n' "${find_error_count:-0}"
printf 'FIND_ERRORS=%s\n' "$find_errors"
printf 'DMESG_ISSUES=%s\n' "$dmesg_issues"
'@
    }

    $result = Invoke-WslDistroCommand -DistroName $Distro.Name -Command $command
    $map = Convert-KeyValueLines -Lines $result.Stdout

    $rootValue = ""
    if ($map.ContainsKey("ROOT_DF")) {
        $rootValue = [string]$map["ROOT_DF"]
    }

    $rootParts = @($rootValue -split "\|")
    while ($rootParts.Count -lt 4) {
        $rootParts += ""
    }

    $inodeValue = ""
    if ($map.ContainsKey("INODE_DF")) {
        $inodeValue = [string]$map["INODE_DF"]
    }

    $inodeParts = @($inodeValue -split "\|")
    while ($inodeParts.Count -lt 4) {
        $inodeParts += ""
    }

    $rootTotalBytes = (ConvertTo-Int64Default -Value $rootParts[0]) * 1KB
    $rootUsedBytes = (ConvertTo-Int64Default -Value $rootParts[1]) * 1KB
    $rootFreeBytes = (ConvertTo-Int64Default -Value $rootParts[2]) * 1KB
    $rootUsedPercent = ConvertTo-PercentInt -Value $rootParts[3]
    $inodeUsedPercent = ConvertTo-PercentInt -Value $inodeParts[3]

    $tmpSockets = ConvertTo-Int64Default -Value $map["TMP_SOCKETS"]
    $varTmpSockets = ConvertTo-Int64Default -Value $map["VAR_TMP_SOCKETS"]
    $sshSockets = ConvertTo-Int64Default -Value $map["SSH_AGENT_SOCKETS"]
    $temporarySockets = $tmpSockets + $varTmpSockets + $sshSockets
    $allSockets = ConvertTo-Int64Default -Value $map["ALL_SOCKETS"] -Default $temporarySockets
    $brokenLinks = ConvertTo-Int64Default -Value $map["BROKEN_LINKS"]
    $rootReadOnly = (ConvertTo-Int64Default -Value $map["ROOT_READONLY"]) -eq 1
    $tmpWritable = (ConvertTo-Int64Default -Value $map["TMP_WRITABLE"] -Default 1) -eq 1
    $homeWritable = (ConvertTo-Int64Default -Value $map["HOME_WRITABLE"] -Default 1) -eq 1
    $findErrorCount = ConvertTo-Int64Default -Value $map["FIND_ERROR_COUNT"]

    $warnings = @()

    if ($result.ExitCode -ne 0) {
        $warnings += "distro nao respondeu via sh"
    }

    if ($rootUsedPercent -ge 90) {
        $warnings += "uso de disco alto ($rootUsedPercent%)"
    }

    if ($inodeUsedPercent -ge 90) {
        $warnings += "uso de inodes alto ($inodeUsedPercent%)"
    }

    if ($temporarySockets -gt 0) {
        $warnings += "$temporarySockets socket(s) temporario(s)"
    }

    if ($Deep.IsPresent -and $allSockets -gt $temporarySockets) {
        $warnings += "$($allSockets - $temporarySockets) socket(s) fora dos locais temporarios"
    }

    if ($Deep.IsPresent -and $rootReadOnly) {
        $warnings += "filesystem raiz montado como read-only"
    }

    if ($Deep.IsPresent -and -not $tmpWritable) {
        $warnings += "/tmp nao aceitou escrita"
    }

    if ($Deep.IsPresent -and -not $homeWritable) {
        $warnings += "`$HOME nao aceitou escrita"
    }

    if ($Deep.IsPresent -and $findErrorCount -gt 0) {
        $warnings += "$findErrorCount erro(s) ao varrer diretorios"
    }

    if ($Deep.IsPresent -and -not [string]::IsNullOrWhiteSpace([string]$map["DMESG_ISSUES"])) {
        $warnings += "dmesg tem sinais de erro/corrupcao/read-only"
    }

    $status = "OK"

    if ($result.ExitCode -ne 0) {
        $status = "ERROR"
    }
    elseif ($warnings.Count -gt 0) {
        $status = "WARN"
    }

    return [PSCustomObject]@{
        Name                  = $Distro.Name
        Status                = $status
        WslCommandExitCode    = $result.ExitCode
        SourceVhdx            = $Distro.SourceVhdx
        SourceVhdxBytes       = [Int64]$Distro.SourceVhdxBytes
        SourceVhdxSize        = $Distro.SourceVhdxSize
        RootTotalBytes        = [Int64]$rootTotalBytes
        RootUsedBytes         = [Int64]$rootUsedBytes
        RootFreeBytes         = [Int64]$rootFreeBytes
        RootUsedPercent       = [int]$rootUsedPercent
        InodeUsedPercent      = [int]$inodeUsedPercent
        TmpSockets            = [Int64]$tmpSockets
        VarTmpSockets         = [Int64]$varTmpSockets
        SshAgentSockets       = [Int64]$sshSockets
        TemporarySockets      = [Int64]$temporarySockets
        AllSockets            = [Int64]$allSockets
        BrokenLinks           = [Int64]$brokenLinks
        RootMountOptions      = [string]$map["ROOT_OPTIONS"]
        RootReadOnly          = [bool]$rootReadOnly
        TmpWritable           = [bool]$tmpWritable
        HomeWritable          = [bool]$homeWritable
        FindErrorCount        = [Int64]$findErrorCount
        FindErrors            = [string]$map["FIND_ERRORS"]
        DmesgIssues           = [string]$map["DMESG_ISSUES"]
        CacheSizes            = [string]$map["CACHE_SIZES"]
        TopRootDirs           = [string]$map["TOP_ROOT_DIRS"]
        Warnings              = @($warnings)
        Stderr                = @($result.Stderr)
        Deep                  = [bool]$Deep
    }
}

function Write-DistroHealth {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Health
    )

    $level = switch ($Health.Status) {
        "OK" { "OK" }
        "WARN" { "WARN" }
        default { "ERROR" }
    }

    Write-Status -Level $level -Message (
        "Saude $($Health.Name): $($Health.Status) | " +
        "/ usado: $($Health.RootUsedPercent)% | " +
        "/ livre: $(Format-Size $Health.RootFreeBytes) | " +
        "inodes: $($Health.InodeUsedPercent)% | " +
        "sockets temporarios: $($Health.TemporarySockets) | " +
        "VHDX: $($Health.SourceVhdxSize)"
    )

    if ($Health.Warnings.Count -gt 0) {
        Write-Status -Level "WARN" -Message (
            "Alertas $($Health.Name): " + ($Health.Warnings -join "; ")
        )
    }

    if ($Health.Deep) {
        Write-Status -Level "INFO" -Message (
            "Diagnostico pesado $($Health.Name): " +
            "sockets totais: $($Health.AllSockets) | " +
            "links quebrados: $($Health.BrokenLinks) | " +
            "root read-only: $($Health.RootReadOnly) | " +
            "/tmp escrita: $($Health.TmpWritable) | " +
            "`$HOME escrita: $($Health.HomeWritable) | " +
            "erros find: $($Health.FindErrorCount)"
        )

        if (-not [string]::IsNullOrWhiteSpace($Health.RootMountOptions)) {
            Write-Status -Level "INFO" -Message "Mount / $($Health.Name): $($Health.RootMountOptions)"
        }

        if (-not [string]::IsNullOrWhiteSpace($Health.CacheSizes)) {
            Write-Status -Level "INFO" -Message "Tamanhos de cache $($Health.Name): $($Health.CacheSizes)"
        }

        if (-not [string]::IsNullOrWhiteSpace($Health.TopRootDirs)) {
            Write-Status -Level "INFO" -Message "Maiores diretorios $($Health.Name): $($Health.TopRootDirs)"
        }

        if (-not [string]::IsNullOrWhiteSpace($Health.FindErrors)) {
            Write-Status -Level "WARN" -Message "Erros de diretorio $($Health.Name): $($Health.FindErrors)"
        }

        if (-not [string]::IsNullOrWhiteSpace($Health.DmesgIssues)) {
            Write-Status -Level "WARN" -Message "Sinais no dmesg $($Health.Name): $($Health.DmesgIssues)"
        }
    }

    foreach ($line in @($Health.Stderr)) {
        $cleanLine = ([string]$line).Replace([string][char]0, "").Trim()

        if (-not [string]::IsNullOrWhiteSpace($cleanLine)) {
            Write-Status -Level "WARN" -Message "Saude $($Health.Name): $cleanLine"
        }
    }
}

function Get-DistroHealthGateIssues {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Health,

        [Parameter(Mandatory)]
        [ValidateSet("Basic", "Standard", "Template")]
        [string]$QualityGate
    )

    $issues = @()

    if ($Health.WslCommandExitCode -ne 0) {
        $issues += "nao respondeu ao comando de saude"
    }

    if ($QualityGate -in @("Standard", "Template")) {
        if ($Health.RootReadOnly) {
            $issues += "filesystem raiz read-only"
        }

        if (-not $Health.TmpWritable) {
            $issues += "/tmp sem escrita"
        }

        if (-not $Health.HomeWritable) {
            $issues += "`$HOME sem escrita"
        }

        if ($Health.FindErrorCount -gt 0) {
            $issues += "$($Health.FindErrorCount) erro(s) ao varrer diretorios"
        }

        if ($Health.RootUsedPercent -ge 95) {
            $issues += "uso de disco critico ($($Health.RootUsedPercent)%)"
        }

        if ($Health.InodeUsedPercent -ge 95) {
            $issues += "uso de inodes critico ($($Health.InodeUsedPercent)%)"
        }

        if (-not [string]::IsNullOrWhiteSpace($Health.DmesgIssues)) {
            $issues += "dmesg indica possivel erro real de filesystem"
        }
    }

    if ($QualityGate -eq "Template") {
        if ($Health.TemporarySockets -gt 0) {
            $issues += "$($Health.TemporarySockets) socket(s) temporario(s)"
        }

        if ($Health.AllSockets -gt 0) {
            $issues += "$($Health.AllSockets) socket(s) total(is) no filesystem"
        }

        if ($Health.RootUsedPercent -ge 90) {
            $issues += "uso de disco alto para template ($($Health.RootUsedPercent)%)"
        }

        if ($Health.InodeUsedPercent -ge 90) {
            $issues += "uso de inodes alto para template ($($Health.InodeUsedPercent)%)"
        }
    }

    return @($issues)
}

function Assert-DistroHealthGate {
    param(
        [array]$HealthResults,

        [Parameter(Mandatory)]
        [ValidateSet("Basic", "Standard", "Template")]
        [string]$QualityGate
    )

    if ($QualityGate -eq "Basic") {
        Write-Status -Level "INFO" -Message "QualityGate Basic: diagnostico informativo, sem bloqueio por avisos."
        return
    }

    $allIssues = @()

    foreach ($health in @($HealthResults)) {
        $issues = Get-DistroHealthGateIssues `
            -Health $health `
            -QualityGate $QualityGate

        foreach ($issue in $issues) {
            $allIssues += "$($health.Name): $issue"
        }
    }

    if ($allIssues.Count -eq 0) {
        Write-Status -Level "OK" -Message "QualityGate $QualityGate aprovado para as distros avaliadas."
        return
    }

    foreach ($issue in $allIssues) {
        Write-Status -Level "ERROR" -Message "QualityGate ${QualityGate}: $issue"
    }

    throw "QualityGate $QualityGate reprovado. Corrija os itens acima ou rode com -QualityGate Basic para apenas relatar."
}

function Clear-WslDistroSockets {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Distro
    )

    $command = @'
tmp_before=$(find /tmp -xdev -type s 2>/dev/null | wc -l | tr -d " ")
var_tmp_before=$(find /var/tmp -xdev -type s 2>/dev/null | wc -l | tr -d " ")
ssh_before=0
for agent_dir in /home/*/.ssh/agent /root/.ssh/agent "$HOME/.ssh/agent"; do
  if [ -d "$agent_dir" ]; then
    count=$(find "$agent_dir" -type s 2>/dev/null | wc -l | tr -d " ")
    ssh_before=$((ssh_before + count))
  fi
done
find /tmp -xdev -type s -delete 2>/dev/null || true
find /var/tmp -xdev -type s -delete 2>/dev/null || true
for agent_dir in /home/*/.ssh/agent /root/.ssh/agent "$HOME/.ssh/agent"; do
  if [ -d "$agent_dir" ]; then
    find "$agent_dir" -type s -delete 2>/dev/null || true
  fi
done
tmp_after=$(find /tmp -xdev -type s 2>/dev/null | wc -l | tr -d " ")
var_tmp_after=$(find /var/tmp -xdev -type s 2>/dev/null | wc -l | tr -d " ")
ssh_after=0
for agent_dir in /home/*/.ssh/agent /root/.ssh/agent "$HOME/.ssh/agent"; do
  if [ -d "$agent_dir" ]; then
    count=$(find "$agent_dir" -type s 2>/dev/null | wc -l | tr -d " ")
    ssh_after=$((ssh_after + count))
  fi
done
printf 'TMP_BEFORE=%s\n' "${tmp_before:-0}"
printf 'VAR_TMP_BEFORE=%s\n' "${var_tmp_before:-0}"
printf 'SSH_BEFORE=%s\n' "${ssh_before:-0}"
printf 'TMP_AFTER=%s\n' "${tmp_after:-0}"
printf 'VAR_TMP_AFTER=%s\n' "${var_tmp_after:-0}"
printf 'SSH_AFTER=%s\n' "${ssh_after:-0}"
'@

    $result = Invoke-WslDistroCommand -DistroName $Distro.Name -Command $command -User "root"
    $map = Convert-KeyValueLines -Lines $result.Stdout

    $before = (ConvertTo-Int64Default -Value $map["TMP_BEFORE"]) +
        (ConvertTo-Int64Default -Value $map["VAR_TMP_BEFORE"]) +
        (ConvertTo-Int64Default -Value $map["SSH_BEFORE"])

    $after = (ConvertTo-Int64Default -Value $map["TMP_AFTER"]) +
        (ConvertTo-Int64Default -Value $map["VAR_TMP_AFTER"]) +
        (ConvertTo-Int64Default -Value $map["SSH_AFTER"])

    $removed = [Math]::Max(0, $before - $after)

    if ($result.ExitCode -eq 0) {
        Write-Status -Level "OK" -Message (
            "Limpeza $($Distro.Name): $removed socket(s) temporario(s) removido(s)."
        )
    }
    else {
        Write-Status -Level "WARN" -Message (
            "Limpeza $($Distro.Name): comando retornou codigo $($result.ExitCode). Backup continuara."
        )
    }

    foreach ($line in @($result.Stderr)) {
        $cleanLine = ([string]$line).Replace([string][char]0, "").Trim()

        if (-not [string]::IsNullOrWhiteSpace($cleanLine)) {
            Write-Status -Level "WARN" -Message "Limpeza $($Distro.Name): $cleanLine"
        }
    }

    return [PSCustomObject]@{
        Name       = $Distro.Name
        Before     = [Int64]$before
        After      = [Int64]$after
        Removed    = [Int64]$removed
        ExitCode   = [int]$result.ExitCode
        Status     = if ($result.ExitCode -eq 0) { "OK" } else { "WARN" }
    }
}

function Invoke-WslDistroTemplatePurify {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Distro
    )

    Write-Status -Level "INFO" -Message "Purificando distro para template: $($Distro.Name)"

    $cleanup = Clear-WslDistroSockets -Distro $Distro

    $command = @'
journal_status="not-found"
if command -v journalctl >/dev/null 2>&1; then
  journal_status="attempted"
  journalctl --rotate >/dev/null 2>&1 || true
  journalctl --vacuum-time=7d >/dev/null 2>&1 || true
fi
sync
printf 'JOURNAL_STATUS=%s\n' "$journal_status"
'@

    $result = Invoke-WslDistroCommand -DistroName $Distro.Name -Command $command -User "root"
    $map = Convert-KeyValueLines -Lines $result.Stdout
    $journalStatus = [string]$map["JOURNAL_STATUS"]

    if ([string]::IsNullOrWhiteSpace($journalStatus)) {
        $journalStatus = "unknown"
    }

    if ($result.ExitCode -eq 0) {
        Write-Status -Level "OK" -Message (
            "Purificacao $($Distro.Name): sockets removidos=$($cleanup.Removed), journal=$journalStatus."
        )
    }
    else {
        Write-Status -Level "WARN" -Message (
            "Purificacao $($Distro.Name): comando extra retornou codigo $($result.ExitCode)."
        )
    }

    foreach ($line in @($result.Stderr)) {
        $cleanLine = ([string]$line).Replace([string][char]0, "").Trim()

        if (-not [string]::IsNullOrWhiteSpace($cleanLine)) {
            Write-Status -Level "WARN" -Message "Purificacao $($Distro.Name): $cleanLine"
        }
    }

    return [PSCustomObject]@{
        Name          = $Distro.Name
        SocketsBefore = [Int64]$cleanup.Before
        SocketsAfter  = [Int64]$cleanup.After
        Removed       = [Int64]$cleanup.Removed
        Journal       = $journalStatus
        ExitCode      = [int]$result.ExitCode
        Status        = if ($result.ExitCode -eq 0 -and $cleanup.ExitCode -eq 0) { "OK" } else { "WARN" }
    }
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

    $exportStdout = "$partialTar.stdout.log"
    $exportStderr = "$partialTar.stderr.log"

    Remove-Item -LiteralPath $exportStdout, $exportStderr -Force -ErrorAction SilentlyContinue

    & wsl.exe --export $Distro.Name $partialTar 1>$exportStdout 2>$exportStderr
    $exportExitCode = $LASTEXITCODE

    foreach ($line in @(Get-TextFileLines -Path $exportStdout -Oem)) {
        $cleanLine = ConvertTo-SafeLogText -Value $line

        if (-not [string]::IsNullOrWhiteSpace($cleanLine)) {
            Write-Status -Level "INFO" -Message "wsl export: $cleanLine"
        }
    }

    foreach ($line in @(Get-TextFileLines -Path $exportStderr -Oem)) {
        $cleanLine = ConvertTo-SafeLogText -Value $line

        if (-not [string]::IsNullOrWhiteSpace($cleanLine)) {
            Write-Status -Level "WARN" -Message "wsl export: $cleanLine"
        }
    }

    Remove-Item -LiteralPath $exportStdout, $exportStderr -Force -ErrorAction SilentlyContinue

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
        "4. Cada TAR tambem pode ser usado como template para criar clones.",
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
            $cloneName = "$($distro.Name)-clone"
            $clonePath = "D:\WSL-Restored\$targetName-clone"
            $tarPath = Join-Path $FinalRunPath $distro.File

            $lines += ""
            $lines += "Restaurar com o mesmo nome:"
            $lines += (
                "wsl.exe --import `"$($distro.Name)`" " +
                "`"$targetPath`" " +
                "`"$tarPath`" --version 2"
            )
            $lines += "Usar como template/clone:"
            $lines += (
                "wsl.exe --import `"$cloneName`" " +
                "`"$clonePath`" " +
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

        [array]$DistroHealth,

        [array]$CleanupResults,

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
            QualityGate       = $Config.QualityGate
            HashAlgorithm     = $Config.HashAlgorithm
            IncludeDocker     = $Config.IncludeDocker
            SkipVhdx          = $Config.SkipVhdx
            CleanWslSockets   = $Config.CleanWslSockets
            PurifyOnly        = $Config.PurifyOnly
            HealthOnly        = $Config.HealthOnly
            DeepHealth        = $Config.DeepHealth
            AutoResume        = $Config.AutoResume
            SourceVhdx        = $Config.SourceVhdx
            KeepLastRuns      = $Config.KeepLastRuns
            MinimumFreeGB     = $Config.MinimumFreeSpaceGB
        }

        Estimate       = $Estimate
        Distros        = $Distros
        SkippedDistros = $SkippedDistros
        DistroHealth   = $DistroHealth
        CleanupResults = $CleanupResults
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
        CleanWslSockets     = $Config.CleanWslSockets
        DeepHealth          = $Config.DeepHealth
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
$distroHealth = @()
$cleanupResults = @()
$templatePurifiedBeforeHealth = $false

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

    if (-not $DryRun.IsPresent -and -not $HealthOnly.IsPresent -and -not $PurifyOnly.IsPresent -and $Config.AutoResume) {
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
    Write-Status -Level "INFO" -Message "QualityGate: $($Config.QualityGate)"
    Write-Status -Level "INFO" -Message "Retomada automatica: $($Config.AutoResume)"
    Write-Status -Level "INFO" -Message "HealthOnly: $($Config.HealthOnly)"
    Write-Status -Level "INFO" -Message "DeepHealth: $($Config.DeepHealth)"
    Write-Status -Level "INFO" -Message "Limpeza de sockets: $($Config.CleanWslSockets)"
    Write-Status -Level "INFO" -Message "PurifyOnly: $($Config.PurifyOnly)"
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

        if (
            $Config.PurifyOnly -or
            (
                $Config.QualityGate -eq "Template" -and
                -not $HealthOnly.IsPresent -and
                -not $DryRun.IsPresent
            )
        ) {
            Write-Section "PURIFICAR DISTROS PARA TEMPLATE"

            foreach ($distro in $selectedDistros) {
                $cleanupResults += Invoke-WslDistroTemplatePurify -Distro $distro
            }

            $templatePurifiedBeforeHealth = $true
        }

        Write-Section "SAUDE DAS DISTROS"

        foreach ($distro in $selectedDistros) {
            $health = Get-WslDistroHealth `
                -Distro $distro `
                -Deep:([bool]$Config.DeepHealth)

            $distroHealth += $health
            Write-DistroHealth -Health $health
        }

        Assert-DistroHealthGate `
            -HealthResults $distroHealth `
            -QualityGate $Config.QualityGate
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

    if ($PurifyOnly.IsPresent) {
        Write-Section "PURIFICACAO CONCLUIDA"
        Write-Status -Level "OK" -Message "PurifyOnly ativo: distros purificadas e diagnosticadas. Nenhum backup foi exportado, copiado ou publicado."
        $backupCompleted = $true
    }
    elseif ($HealthOnly.IsPresent) {
        Write-Section "DIAGNOSTICO CONCLUIDO"
        Write-Status -Level "OK" -Message "HealthOnly ativo: nenhum backup foi exportado, copiado ou publicado."
        $backupCompleted = $true
    }
    elseif ($DryRun.IsPresent) {
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

        if ($needsDistros -and $Config.CleanWslSockets -and -not $templatePurifiedBeforeHealth) {
            Write-Section "PREPARAR DISTROS PARA BACKUP/TEMPLATE"

            foreach ($distro in $selectedDistros) {
                $cleanupResults += Clear-WslDistroSockets -Distro $distro
            }
        }
        elseif ($templatePurifiedBeforeHealth) {
            Write-Status -Level "INFO" -Message "Purificacao de template ja executada antes do diagnostico."
        }
        elseif ($needsDistros) {
            Write-Status -Level "INFO" -Message "Limpeza de sockets nao solicitada. Use -CleanWslSockets para preparar as distros antes do export."
        }

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
            -DistroHealth $distroHealth `
            -CleanupResults $cleanupResults `
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
