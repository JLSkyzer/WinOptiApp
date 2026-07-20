$Script:LogDir = Join-Path $env:LOCALAPPDATA 'WinOptiApp'
$Script:BackupDir = Join-Path $Script:LogDir 'backups'
$Script:StateDir = Join-Path $Script:LogDir 'state'
$Script:LogFile = Join-Path $Script:LogDir 'engine.log'

foreach ($dir in @($Script:LogDir, $Script:BackupDir, $Script:StateDir)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

function Write-EngineLog {
    param([string]$Message, [ValidateSet('INFO', 'OK', 'WARN', 'ERREUR')][string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $Script:LogFile -Value $line -Encoding UTF8
}

function New-EngineResult {
    param([bool]$Ok, $Data = $null, [string]$ErrorMessage = $null)
    return [PSCustomObject]@{ ok = $Ok; data = $Data; error = $ErrorMessage }
}

function Get-StatePath {
    param([string]$Name)
    return Join-Path $Script:StateDir "$Name.json"
}

function Save-EngineState {
    param([string]$Name, $Value)
    $Value | ConvertTo-Json -Depth 10 | Set-Content -Path (Get-StatePath $Name) -Encoding UTF8
}

function Get-EngineState {
    param([string]$Name)
    $p = Get-StatePath $Name
    if (-not (Test-Path $p)) { return $null }
    try { return Get-Content $p -Raw | ConvertFrom-Json } catch { return $null }
}

function Backup-RegistryKey {
    param([string]$KeyPath, [string]$BackupName)
    try {
        $probe = Get-Item -Path $KeyPath -ErrorAction SilentlyContinue
        if (-not $probe) {
            Write-EngineLog "Cle absente, pas de backup necessaire: $KeyPath" 'INFO'
            return $null
        }
        $regPath = $KeyPath -replace '^HKLM:', 'HKEY_LOCAL_MACHINE' -replace '^HKCU:', 'HKEY_CURRENT_USER'
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $file = Join-Path $Script:BackupDir "$BackupName-$stamp.reg"
        & reg.exe export "$regPath" "$file" /y 2>&1 | Out-Null
        Write-EngineLog "Backup registre: $regPath -> $file" 'OK'
        return $file
    } catch {
        Write-EngineLog "Echec backup registre $KeyPath : $($_.Exception.Message)" 'WARN'
        return $null
    }
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    } catch {
        return $null
    }
}

function Set-RegValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Remove-RegValue {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path $Path)) { return }
    $existing = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $existing) { return }
    Remove-ItemProperty -Path $Path -Name $Name
}

function Test-IsElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ServiceStartupType {
    param([string]$ServiceName)
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) { return $null }
    return (Get-CimInstance -ClassName Win32_Service -Filter "Name='$ServiceName'").StartMode
}

function Set-ServiceState {
    param([string]$ServiceName, [string]$StartupType, [switch]$StopNow)
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-EngineLog "Service introuvable: $ServiceName" 'WARN'
        return
    }
    Set-Service -Name $ServiceName -StartupType $StartupType
    if ($StopNow -and $StartupType -eq 'Disabled') {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    }
    Write-EngineLog "Service $ServiceName -> $StartupType" 'OK'
}

function Test-DeviceClassPresent {
    param([string]$ClassName)
    $devices = Get-PnpDevice -Class $ClassName -Status OK -ErrorAction SilentlyContinue
    return (@($devices).Count -gt 0)
}
