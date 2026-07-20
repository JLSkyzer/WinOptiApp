param(
    [Parameter(Mandatory = $true)][string]$Action,
    [string]$PayloadPath
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptRoot 'Common.ps1')

$CatalogPath = Join-Path (Split-Path $ScriptRoot -Parent) 'data\tweaks-catalog.json'
$Script:Catalog = Get-Content $CatalogPath -Raw | ConvertFrom-Json

$Script:Payload = $null
if ($PayloadPath -and (Test-Path $PayloadPath)) {
    $Script:Payload = Get-Content $PayloadPath -Raw | ConvertFrom-Json
}

function Get-CatalogEntry {
    param([string]$Id)
    return $Script:Catalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

# ============================================================
# Etat / application generique (kind: registry | service | handler)
# ============================================================

function Get-ToggleState {
    param($Entry)
    switch ($Entry.kind) {
        'registry' {
            $current = Get-RegValue -Path $Entry.path -Name $Entry.name
            if ($null -eq $current) {
                if ($null -eq $Entry.defaultValue -or "$($Entry.defaultValue)" -eq "$($Entry.offValue)") { return 'off' }
                return 'off'
            }
            if ("$current" -eq "$($Entry.onValue)") { return 'on' } else { return 'off' }
        }
        'service' {
            $st = Get-ServiceStartupType -ServiceName $Entry.serviceName
            if ($null -eq $st) { return 'unknown' }
            if ("$st" -eq "$($Entry.onValue)") { return 'on' } else { return 'off' }
        }
        'handler' {
            $fn = "Get-HandlerState_$($Entry.handler)"
            if (Get-Command $fn -ErrorAction SilentlyContinue) { return (& $fn) }
            return 'unknown'
        }
        default { return 'unknown' }
    }
}

function Set-ToggleValue {
    param($Entry, [bool]$Enabled)
    switch ($Entry.kind) {
        'registry' {
            Backup-RegistryKey -KeyPath $Entry.path -BackupName $Entry.id | Out-Null
            $target = if ($Enabled) { $Entry.onValue } else { $Entry.offValue }
            if ($null -eq $target) {
                Remove-RegValue -Path $Entry.path -Name $Entry.name
            } else {
                Set-RegValue -Path $Entry.path -Name $Entry.name -Value $target -Type $Entry.regType
            }
            Write-EngineLog "Toggle registre '$($Entry.id)' -> $Enabled" 'OK'
        }
        'service' {
            $target = if ($Enabled) { $Entry.onValue } else { $Entry.offValue }
            Set-ServiceState -ServiceName $Entry.serviceName -StartupType $target
        }
        'handler' {
            $fn = "Set-HandlerState_$($Entry.handler)"
            if (Get-Command $fn -ErrorAction SilentlyContinue) {
                & $fn -Enabled $Enabled
            } else {
                throw "Handler introuvable: $($Entry.handler)"
            }
        }
        default { throw "Type de tweak inconnu pour '$($Entry.id)'" }
    }
}

function Get-DefaultEnabled {
    param($Entry)
    if ($Entry.kind -eq 'handler') { return $false }
    if ($null -eq $Entry.defaultValue) { return $false }
    return ("$($Entry.defaultValue)" -eq "$($Entry.onValue)")
}

# ============================================================
# Handlers nommes : Plans d'alimentation
# ============================================================

$Script:GuidHighPerf = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$Script:GuidBalanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
$Script:GuidUltimateHidden = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$Script:GuidSubUsb = '2a737441-1930-4402-8d77-b2bebba308a3'
$Script:GuidUsbSelectSuspend = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'

function Get-ActiveSchemeGuid {
    $out = & powercfg /getactivescheme
    if ($out -match '([0-9a-fA-F-]{36})') { return $matches[1] }
    return $null
}

function Get-HandlerState_PowerPlanHighPerf {
    $active = Get-ActiveSchemeGuid
    if ($active -and $active.ToLower() -eq $Script:GuidHighPerf) { return 'on' }
    return 'off'
}

function Set-HandlerState_PowerPlanHighPerf {
    param([bool]$Enabled)
    if ($Enabled) {
        & powercfg /setactive $Script:GuidHighPerf | Out-Null
        Write-EngineLog 'Plan Performances elevees active' 'OK'
    } else {
        $active = Get-ActiveSchemeGuid
        if ($active -and $active.ToLower() -eq $Script:GuidHighPerf) {
            & powercfg /setactive $Script:GuidBalanced | Out-Null
            Write-EngineLog 'Retour au plan Equilibre' 'OK'
        }
    }
}

function Get-HandlerState_PowerPlanUltimate {
    $state = Get-EngineState 'power-plan-ultimate'
    if ($state -and $state.guid) {
        $active = Get-ActiveSchemeGuid
        if ($active -and $active.ToLower() -eq $state.guid.ToLower()) { return 'on' }
    }
    return 'off'
}

function Set-HandlerState_PowerPlanUltimate {
    param([bool]$Enabled)
    if ($Enabled) {
        $out = & powercfg -duplicatescheme $Script:GuidUltimateHidden
        $newGuid = $null
        if ($out -match '([0-9a-fA-F-]{36})') { $newGuid = $matches[1] }
        if (-not $newGuid) { throw 'Impossible de dupliquer le plan Ultimate Performance.' }
        & powercfg /setactive $newGuid | Out-Null
        & powercfg /setacvalueindex $newGuid SUB_PROCESSOR PROCTHROTTLEMIN 100 | Out-Null
        & powercfg /setdcvalueindex $newGuid SUB_PROCESSOR PROCTHROTTLEMIN 100 | Out-Null
        & powercfg /setacvalueindex $newGuid SUB_PCIEXPRESS ASPM 0 | Out-Null
        & powercfg /setacvalueindex $newGuid $Script:GuidSubUsb $Script:GuidUsbSelectSuspend 0 | Out-Null
        & powercfg /setdcvalueindex $newGuid $Script:GuidSubUsb $Script:GuidUsbSelectSuspend 0 | Out-Null
        Save-EngineState 'power-plan-ultimate' @{ guid = $newGuid }
        Write-EngineLog "Plan Ultimate Performance duplique et active ($newGuid)" 'OK'
    } else {
        $state = Get-EngineState 'power-plan-ultimate'
        & powercfg /setactive $Script:GuidBalanced | Out-Null
        if ($state -and $state.guid) {
            & powercfg -delete $state.guid 2>&1 | Out-Null
            Write-EngineLog "Plan Ultimate Performance supprime ($($state.guid))" 'OK'
        }
        Save-EngineState 'power-plan-ultimate' @{ guid = $null }
    }
}

function Get-HandlerState_UsbSelectiveSuspend {
    $out = & powercfg /q SCHEME_CURRENT $Script:GuidSubUsb $Script:GuidUsbSelectSuspend 2>&1
    if ($out -match "actuel du paramètre de courant alternatif\s*:\s*0x0*0\b" -or $out -match 'Current AC Power Setting Index:\s*0x0*0\b') { return 'on' }
    return 'off'
}

function Set-HandlerState_UsbSelectiveSuspend {
    param([bool]$Enabled)
    $value = if ($Enabled) { 0 } else { 1 }
    & powercfg /setacvalueindex SCHEME_CURRENT $Script:GuidSubUsb $Script:GuidUsbSelectSuspend $value | Out-Null
    & powercfg /setdcvalueindex SCHEME_CURRENT $Script:GuidSubUsb $Script:GuidUsbSelectSuspend $value | Out-Null
    & powercfg /setactive SCHEME_CURRENT | Out-Null
    Write-EngineLog "Veille selective USB -> Enabled=$Enabled" 'OK'
}

# ============================================================
# Handlers nommes : Reseau
# ============================================================

function Get-HandlerState_NetworkNagle {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    if (-not (Test-Path $base)) { return 'off' }
    $ifaces = Get-ChildItem $base -ErrorAction SilentlyContinue
    foreach ($i in $ifaces) {
        $v = Get-RegValue -Path $i.PSPath -Name 'TcpAckFrequency'
        if ("$v" -eq '1') { return 'on' }
    }
    return 'off'
}

function Set-HandlerState_NetworkNagle {
    param([bool]$Enabled)
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    $ifaces = Get-ChildItem $base -ErrorAction SilentlyContinue
    foreach ($i in $ifaces) {
        if ($Enabled) {
            Set-RegValue -Path $i.PSPath -Name 'TcpAckFrequency' -Value 1 -Type DWord
            Set-RegValue -Path $i.PSPath -Name 'TCPNoDelay' -Value 1 -Type DWord
        } else {
            Remove-RegValue -Path $i.PSPath -Name 'TcpAckFrequency'
            Remove-RegValue -Path $i.PSPath -Name 'TCPNoDelay'
        }
    }
    Write-EngineLog "Nagle -> Enabled=$Enabled sur $(@($ifaces).Count) interface(s)" 'OK'
}

function Get-HandlerState_NetworkRSS {
    $adapters = Get-NetAdapterRss -ErrorAction SilentlyContinue
    foreach ($a in $adapters) { if ($a.Enabled) { return 'on' } }
    return 'off'
}

function Set-HandlerState_NetworkRSS {
    param([bool]$Enabled)
    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue
    foreach ($a in $adapters) {
        try {
            if ($Enabled) { Enable-NetAdapterRss -Name $a.Name -ErrorAction SilentlyContinue }
            else { Disable-NetAdapterRss -Name $a.Name -ErrorAction SilentlyContinue }
        } catch {
            Write-EngineLog "RSS: echec sur $($a.Name): $($_.Exception.Message)" 'WARN'
        }
    }
    Write-EngineLog "RSS -> Enabled=$Enabled" 'OK'
}

function Get-HandlerState_NetworkEEE {
    $props = Get-NetAdapterAdvancedProperty -DisplayName '*Energy Efficient*' -ErrorAction SilentlyContinue
    if (-not $props) { return 'unknown' }
    foreach ($p in $props) { if ($p.DisplayValue -notmatch 'Disabled|Off|Desactive') { return 'off' } }
    return 'on'
}

function Set-HandlerState_NetworkEEE {
    param([bool]$Enabled)
    $props = Get-NetAdapterAdvancedProperty -DisplayName '*Energy Efficient*' -ErrorAction SilentlyContinue
    if (-not $props) { return }
    if ($Enabled) {
        $captured = @()
        foreach ($p in $props) {
            $captured += [PSCustomObject]@{ AdapterName = $p.Name; DisplayName = $p.DisplayName; OriginalValue = $p.DisplayValue }
            try { Set-NetAdapterAdvancedProperty -Name $p.Name -DisplayName $p.DisplayName -DisplayValue 'Disabled' -ErrorAction SilentlyContinue } catch {}
        }
        Save-EngineState 'network-eee' $captured
        Write-EngineLog "EEE desactive sur $(@($props).Count) propriete(s)" 'OK'
    } else {
        $state = Get-EngineState 'network-eee'
        foreach ($p in $props) {
            $original = $null
            if ($state) { $original = ($state | Where-Object { $_.AdapterName -eq $p.Name -and $_.DisplayName -eq $p.DisplayName }).OriginalValue }
            $restoreValue = if ($original) { $original } else { 'Enabled' }
            try { Set-NetAdapterAdvancedProperty -Name $p.Name -DisplayName $p.DisplayName -DisplayValue $restoreValue -ErrorAction SilentlyContinue } catch {}
        }
        Write-EngineLog 'EEE restaure a son etat original' 'OK'
    }
}

# ============================================================
# Handlers nommes : Affichage
# ============================================================

function Get-MsiTargetDevices {
    $gpu = Get-PnpDevice -Class Display -Status OK -ErrorAction SilentlyContinue
    $usb = Get-PnpDevice -Class USB -Status OK -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Host Controller' }
    return @($gpu) + @($usb)
}

function Get-HandlerState_MsiModeGpuUsb {
    $devices = Get-MsiTargetDevices
    if (@($devices).Count -eq 0) { return 'unknown' }
    foreach ($d in $devices) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($d.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        $v = Get-RegValue -Path $path -Name 'MSISupported'
        if ("$v" -ne '1') { return 'off' }
    }
    return 'on'
}

function Set-HandlerState_MsiModeGpuUsb {
    param([bool]$Enabled)
    $devices = Get-MsiTargetDevices
    $value = if ($Enabled) { 1 } else { 0 }
    foreach ($d in $devices) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($d.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        if (Test-Path $path) {
            Backup-RegistryKey -KeyPath $path -BackupName "msi-$($d.InstanceId -replace '[\\\/]','_')" | Out-Null
            Set-RegValue -Path $path -Name 'MSISupported' -Value $value -Type DWord
        }
    }
    Write-EngineLog "MSI Mode -> Enabled=$Enabled sur $(@($devices).Count) peripherique(s)" 'OK'
}

function Get-HandlerState_VisualEffectsPerf {
    $v = Get-RegValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate'
    if ("$v" -eq '0') { return 'on' }
    return 'off'
}

function Set-HandlerState_VisualEffectsPerf {
    param([bool]$Enabled)
    if ($Enabled) {
        Set-RegValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Type String
        Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -Type String
        Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations' -Value 0 -Type DWord
        Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ListviewAlphaSelect' -Value 0 -Type DWord
        Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 3 -Type DWord
    } else {
        Set-RegValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '1' -Type String
        Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '400' -Type String
        Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations' -Value 1 -Type DWord
        Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ListviewAlphaSelect' -Value 1 -Type DWord
        Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 0 -Type DWord
    }
    Write-EngineLog "Effets visuels -> Enabled=$Enabled" 'OK'
}

# ============================================================
# Handlers nommes : Jeux
# ============================================================

function Get-HandlerState_GameDVROverlay {
    $v = Get-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled'
    if ("$v" -eq '0') { return 'on' }
    return 'off'
}

function Set-HandlerState_GameDVROverlay {
    param([bool]$Enabled)
    $dvrValue = if ($Enabled) { 0 } else { 1 }
    Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value $dvrValue -Type DWord
    Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value $dvrValue -Type DWord
    if ($Enabled) {
        Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0 -Type DWord
    } else {
        Remove-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR'
    }
    Write-EngineLog "GameDVR/overlay -> Enabled(desactive)=$Enabled" 'OK'
}

# ============================================================
# Handlers nommes : Confidentialite
# ============================================================

function Get-HandlerState_WidgetsCopilotBing {
    $v = Get-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' -Name 'EnableFeeds'
    if ("$v" -eq '0') { return 'on' }
    return 'off'
}

function Set-HandlerState_WidgetsCopilotBing {
    param([bool]$Enabled)
    $advPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    if ($Enabled) {
        $captured = @{
            TaskbarDa = Get-RegValue -Path $advPath -Name 'TaskbarDa'
            ShowCopilotButton = Get-RegValue -Path $advPath -Name 'ShowCopilotButton'
        }
        Save-EngineState 'widgets-copilot-bing' $captured
        Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' -Name 'EnableFeeds' -Value 0 -Type DWord
        Set-RegValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1 -Type DWord
        Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Value 0 -Type DWord
        Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'CortanaConsent' -Value 0 -Type DWord
        Set-RegValue -Path $advPath -Name 'TaskbarDa' -Value 0 -Type DWord
        Set-RegValue -Path $advPath -Name 'ShowCopilotButton' -Value 0 -Type DWord
    } else {
        Remove-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' -Name 'EnableFeeds'
        Remove-RegValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot'
        Remove-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled'
        Remove-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'CortanaConsent'
        $prev = Get-EngineState 'widgets-copilot-bing'
        $taskbarDaRestore = if ($prev -and $null -ne $prev.TaskbarDa) { $prev.TaskbarDa } else { 1 }
        $copilotBtnRestore = if ($prev -and $null -ne $prev.ShowCopilotButton) { $prev.ShowCopilotButton } else { 1 }
        Set-RegValue -Path $advPath -Name 'TaskbarDa' -Value $taskbarDaRestore -Type DWord
        Set-RegValue -Path $advPath -Name 'ShowCopilotButton' -Value $copilotBtnRestore -Type DWord
    }
    Write-EngineLog "Widgets/Copilot/Bing -> Enabled=$Enabled" 'OK'
}

$Script:TelemetryTasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\Feedback\Siuf\DmClient',
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
)

function Get-HandlerState_ScheduledTasksTelemetry {
    $found = 0
    $disabled = 0
    foreach ($t in $Script:TelemetryTasks) {
        $taskPath = Split-Path $t -Parent
        $taskName = Split-Path $t -Leaf
        $task = Get-ScheduledTask -TaskPath "$taskPath\" -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            $found++
            if ($task.State -eq 'Disabled') { $disabled++ }
        }
    }
    if ($found -eq 0) { return 'unknown' }
    if ($disabled -eq $found) { return 'on' }
    return 'off'
}

function Set-HandlerState_ScheduledTasksTelemetry {
    param([bool]$Enabled)
    foreach ($t in $Script:TelemetryTasks) {
        $taskPath = Split-Path $t -Parent
        $taskName = Split-Path $t -Leaf
        $task = Get-ScheduledTask -TaskPath "$taskPath\" -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $task) { continue }
        try {
            if ($Enabled) { Disable-ScheduledTask -InputObject $task | Out-Null }
            else { Enable-ScheduledTask -InputObject $task | Out-Null }
        } catch {
            Write-EngineLog "Tache '$t': $($_.Exception.Message)" 'WARN'
        }
    }
    Write-EngineLog "Taches telemetrie -> Desactivees=$Enabled" 'OK'
}

# ============================================================
# Handlers nommes : Services (MMCSS)
# ============================================================

function Get-HandlerState_MMCSSGamesPriority {
    $v = Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness'
    if ("$v" -eq '10') { return 'on' }
    return 'off'
}

function Set-HandlerState_MMCSSGamesPriority {
    param([bool]$Enabled)
    $tasksPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
    if ($Enabled) {
        Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness' -Value 10 -Type DWord
        Set-RegValue -Path $tasksPath -Name 'GPU Priority' -Value 8 -Type DWord
        Set-RegValue -Path $tasksPath -Name 'Priority' -Value 6 -Type DWord
        Set-RegValue -Path $tasksPath -Name 'Scheduling Category' -Value 'High' -Type String
        Set-RegValue -Path $tasksPath -Name 'SFIO Priority' -Value 'High' -Type String
    } else {
        Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness' -Value 20 -Type DWord
        Set-RegValue -Path $tasksPath -Name 'GPU Priority' -Value 8 -Type DWord
        Set-RegValue -Path $tasksPath -Name 'Priority' -Value 2 -Type DWord
        Set-RegValue -Path $tasksPath -Name 'Scheduling Category' -Value 'Medium' -Type String
        Set-RegValue -Path $tasksPath -Name 'SFIO Priority' -Value 'Normal' -Type String
    }
    Write-EngineLog "MMCSS jeux -> Enabled=$Enabled" 'OK'
}

# ============================================================
# Listes dynamiques : demarrage, debloat, preference GPU
# ============================================================

$Script:RunKeys = @(
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Hive = 'HKCU' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Hive = 'HKLM' }
)

function Get-StartupApprovedEnabled {
    param([string]$ApprovedPath, [string]$Name)
    if (-not (Test-Path $ApprovedPath)) { return $true }
    $raw = Get-RegValue -Path $ApprovedPath -Name $Name
    if ($null -eq $raw) { return $true }
    if ($raw[0] -eq 3) { return $false }
    return $true
}

function Invoke-ListStartupApps {
    $result = @()
    foreach ($rk in $Script:RunKeys) {
        if (-not (Test-Path $rk.Path)) { continue }
        $props = Get-ItemProperty -Path $rk.Path -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($prop in $props.PSObject.Properties) {
            if ($prop.Name -like 'PS*') { continue }
            $enabled = Get-StartupApprovedEnabled -ApprovedPath $rk.Approved -Name $prop.Name
            $result += [PSCustomObject]@{ name = $prop.Name; command = "$($prop.Value)"; hive = $rk.Hive; enabled = $enabled }
        }
    }
    return ,$result
}

function Invoke-SetStartupApp {
    param($Payload)
    $rk = $Script:RunKeys | Where-Object { $_.Hive -eq $Payload.hive } | Select-Object -First 1
    if (-not $rk) { throw "Hive de demarrage inconnue: $($Payload.hive)" }
    if (-not (Test-Path $rk.Approved)) { New-Item -Path $rk.Approved -Force | Out-Null }
    $bytes = New-Object byte[] 12
    $bytes[0] = if ($Payload.enabled) { 2 } else { 3 }
    New-ItemProperty -Path $rk.Approved -Name $Payload.name -Value $bytes -PropertyType Binary -Force | Out-Null
    Write-EngineLog "Startup '$($Payload.name)' -> enabled=$($Payload.enabled)" 'OK'
}

$Script:BloatKnownRisk = @{
    'BingNews' = 'faible'; 'BingWeather' = 'faible'; 'GetHelp' = 'faible'; 'Getstarted' = 'faible';
    'MicrosoftOfficeHub' = 'faible'; 'MicrosoftSolitaireCollection' = 'faible'; 'People' = 'faible';
    'WindowsFeedbackHub' = 'faible'; 'YourPhone' = 'faible'; 'ZuneMusic' = 'faible'; 'ZuneVideo' = 'faible';
    'MixedReality.Portal' = 'moyen'; 'Xbox.TCUI' = 'moyen'; 'XboxApp' = 'moyen'; 'XboxGameOverlay' = 'moyen';
    'XboxGamingOverlay' = 'moyen'; 'XboxIdentityProvider' = 'moyen'; 'XboxSpeechToTextOverlay' = 'moyen'
}

function Invoke-ListBloatApps {
    $packages = Get-AppxPackage -ErrorAction SilentlyContinue
    $result = @()
    foreach ($p in $packages) {
        $shortParts = $p.Name -split '\.'
        $short = if ($shortParts.Count -ge 2) { ($shortParts[1..($shortParts.Count - 1)] -join '.') } else { $p.Name }
        if (-not $Script:BloatKnownRisk.ContainsKey($short)) { continue }
        $result += [PSCustomObject]@{ name = $p.Name; packageFullName = $p.PackageFullName; risk = $Script:BloatKnownRisk[$short] }
    }
    return ,$result
}

function Invoke-SetBloatApp {
    param($Payload)
    try {
        Get-AppxPackage -Name $Payload.packageFullName -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction Stop
        Write-EngineLog "App supprimee: $($Payload.packageFullName)" 'OK'
    } catch {
        Write-EngineLog "Echec suppression $($Payload.packageFullName): $($_.Exception.Message)" 'WARN'
        throw
    }
}

$Script:GpuPrefPath = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'

function Invoke-ListGpuPrefApps {
    $result = @()
    if (Test-Path $Script:GpuPrefPath) {
        $props = Get-ItemProperty -Path $Script:GpuPrefPath -ErrorAction SilentlyContinue
        if ($props) {
            foreach ($prop in $props.PSObject.Properties) {
                if ($prop.Name -like 'PS*') { continue }
                if ("$($prop.Value)" -match 'GpuPreference=2') {
                    $result += [PSCustomObject]@{ path = $prop.Name }
                }
            }
        }
    }
    return ,$result
}

function Invoke-AddGpuPrefApp {
    param($Payload)
    if (-not (Test-Path $Script:GpuPrefPath)) { New-Item -Path $Script:GpuPrefPath -Force | Out-Null }
    Set-RegValue -Path $Script:GpuPrefPath -Name $Payload.path -Value 'GpuPreference=2;' -Type String
    Write-EngineLog "Preference GPU haute perf ajoutee: $($Payload.path)" 'OK'
}

function Invoke-RemoveGpuPrefApp {
    param($Payload)
    Remove-RegValue -Path $Script:GpuPrefPath -Name $Payload.path
    Write-EngineLog "Preference GPU haute perf retiree: $($Payload.path)" 'OK'
}

# ============================================================
# Points de restauration
# ============================================================

function Invoke-CreateRestorePoint {
    param($Payload)
    $desc = if ($Payload -and $Payload.description) { $Payload.description } else { 'WinOptiApp' }
    try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue } catch {}
    Checkpoint-Computer -Description $desc -RestorePointType 'MODIFY_SETTINGS'
    Write-EngineLog "Point de restauration cree: $desc" 'OK'
}

function Invoke-ListRestorePoints {
    $points = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Select-Object SequenceNumber, Description, CreationTime, RestorePointType)
    return ,$points
}

function Invoke-RestartExplorer {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer.exe
    }
    Write-EngineLog 'Explorateur redemarre' 'OK'
}

# ============================================================
# Etat global / reset
# ============================================================

function Invoke-GetAllStates {
    $result = @()
    foreach ($entry in $Script:Catalog) {
        if (-not $entry.kind) { continue }
        $state = Get-ToggleState -Entry $entry
        $guardOk = $true
        if ($entry.guardNoDeviceClass) {
            $guardOk = -not (Test-DeviceClassPresent -ClassName $entry.guardNoDeviceClass)
        }
        $result += [PSCustomObject]@{ id = $entry.id; state = $state; guardOk = $guardOk }
    }
    return ,$result
}

function Invoke-Apply {
    param($Payload)
    $results = @()
    foreach ($item in $Payload) {
        $entry = Get-CatalogEntry -Id $item.id
        if (-not $entry) {
            $results += [PSCustomObject]@{ id = $item.id; ok = $false; error = 'Tweak inconnu' }
            continue
        }
        try {
            Set-ToggleValue -Entry $entry -Enabled ([bool]$item.enabled)
            $results += [PSCustomObject]@{ id = $entry.id; ok = $true }
        } catch {
            Write-EngineLog "Echec application '$($entry.id)': $($_.Exception.Message)" 'ERREUR'
            $results += [PSCustomObject]@{ id = $entry.id; ok = $false; error = $_.Exception.Message }
        }
    }
    return ,$results
}

function Invoke-ResetCategory {
    param($Payload)
    $category = if ($Payload) { $Payload.category } else { $null }
    $entries = $Script:Catalog | Where-Object { $_.kind -and (-not $category -or $_.category -eq $category) }
    $results = @()
    foreach ($entry in $entries) {
        try {
            Set-ToggleValue -Entry $entry -Enabled (Get-DefaultEnabled -Entry $entry)
            $results += [PSCustomObject]@{ id = $entry.id; ok = $true }
        } catch {
            Write-EngineLog "Echec reset '$($entry.id)': $($_.Exception.Message)" 'ERREUR'
            $results += [PSCustomObject]@{ id = $entry.id; ok = $false; error = $_.Exception.Message }
        }
    }
    return ,$results
}

# ============================================================
# Dispatch principal
# ============================================================

try {
    $data = switch ($Action) {
        'GetAllStates' { Invoke-GetAllStates }
        'Apply' { Invoke-Apply -Payload $Script:Payload }
        'ResetCategory' { Invoke-ResetCategory -Payload $Script:Payload }
        'ListStartupApps' { Invoke-ListStartupApps }
        'SetStartupApp' { Invoke-SetStartupApp -Payload $Script:Payload; $null }
        'ListBloatApps' { Invoke-ListBloatApps }
        'SetBloatApp' { Invoke-SetBloatApp -Payload $Script:Payload; $null }
        'ListGpuPrefApps' { Invoke-ListGpuPrefApps }
        'AddGpuPrefApp' { Invoke-AddGpuPrefApp -Payload $Script:Payload; $null }
        'RemoveGpuPrefApp' { Invoke-RemoveGpuPrefApp -Payload $Script:Payload; $null }
        'CreateRestorePoint' { Invoke-CreateRestorePoint -Payload $Script:Payload; $null }
        'ListRestorePoints' { Invoke-ListRestorePoints }
        'GetEnvironmentInfo' { [PSCustomObject]@{ isAdmin = (Test-IsElevated) } }
        'RestartExplorer' { Invoke-RestartExplorer; $null }
        default { throw "Action inconnue: $Action" }
    }
    $result = New-EngineResult -Ok $true -Data $data
} catch {
    Write-EngineLog "Erreur action '$Action': $($_.Exception.Message)" 'ERREUR'
    $result = New-EngineResult -Ok $false -ErrorMessage $_.Exception.Message
}

$result | ConvertTo-Json -Depth 10 -Compress
