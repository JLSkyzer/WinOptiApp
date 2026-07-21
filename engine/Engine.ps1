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

$Script:GuidSubProcessor = '54533251-82be-4824-96c1-47b60b740d00'
$Script:GuidPerfBoostMode = 'be337238-0d82-4146-a960-4f3749d470c7'

function Get-HandlerState_CpuBoostAggressive {
    $out = & powercfg /q SCHEME_CURRENT $Script:GuidSubProcessor $Script:GuidPerfBoostMode 2>&1
    if ($out -match "actuel du paramètre de courant alternatif\s*:\s*0x0*2\b" -or $out -match 'Current AC Power Setting Index:\s*0x0*2\b') { return 'on' }
    return 'off'
}

function Set-HandlerState_CpuBoostAggressive {
    param([bool]$Enabled)
    $value = if ($Enabled) { 2 } else { 1 }
    & powercfg /setacvalueindex SCHEME_CURRENT $Script:GuidSubProcessor $Script:GuidPerfBoostMode $value | Out-Null
    & powercfg /setdcvalueindex SCHEME_CURRENT $Script:GuidSubProcessor $Script:GuidPerfBoostMode $value | Out-Null
    & powercfg /setactive SCHEME_CURRENT | Out-Null
    Write-EngineLog "Boost CPU agressif -> Enabled=$Enabled" 'OK'
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

function Get-HandlerState_NetworkIPv6Disable {
    $bindings = Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
    if (-not $bindings) { return 'unknown' }
    $anyEnabled = $bindings | Where-Object { $_.Enabled }
    if ($anyEnabled) { return 'off' }
    return 'on'
}

function Set-HandlerState_NetworkIPv6Disable {
    param([bool]$Enabled)
    $bindings = Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
    foreach ($b in $bindings) {
        try {
            if ($Enabled) { Disable-NetAdapterBinding -Name $b.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue }
            else { Enable-NetAdapterBinding -Name $b.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue }
        } catch {
            Write-EngineLog "IPv6: echec sur $($b.Name): $($_.Exception.Message)" 'WARN'
        }
    }
    Write-EngineLog "IPv6 desactive -> Enabled=$Enabled sur $(@($bindings).Count) interface(s)" 'OK'
}

function Get-HandlerState_NetworkPowerManagementDisable {
    $adapters = Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue
    if (-not $adapters) { return 'unknown' }
    $anyAllowed = $adapters | Where-Object { $_.AllowComputerToTurnOffDevice -eq 'Enabled' }
    if ($anyAllowed) { return 'off' }
    return 'on'
}

function Set-HandlerState_NetworkPowerManagementDisable {
    param([bool]$Enabled)
    $adapters = Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue
    $value = if ($Enabled) { 'Disabled' } else { 'Enabled' }
    foreach ($a in $adapters) {
        try { Set-NetAdapterPowerManagement -Name $a.Name -AllowComputerToTurnOffDevice $value -ErrorAction SilentlyContinue } catch {
            Write-EngineLog "Gestion energie reseau: echec sur $($a.Name): $($_.Exception.Message)" 'WARN'
        }
    }
    Write-EngineLog "Gestion d'energie carte reseau -> Enabled(desactivee)=$Enabled" 'OK'
}

function Get-MsiTargetNetworkDevices {
    return @(Get-PnpDevice -Class Net -Status OK -ErrorAction SilentlyContinue)
}

function Get-HandlerState_MsiModeNetwork {
    $devices = Get-MsiTargetNetworkDevices
    if (@($devices).Count -eq 0) { return 'unknown' }
    foreach ($d in $devices) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($d.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        $v = Get-RegValue -Path $path -Name 'MSISupported'
        if ("$v" -ne '1') { return 'off' }
    }
    return 'on'
}

function Set-HandlerState_MsiModeNetwork {
    param([bool]$Enabled)
    $devices = Get-MsiTargetNetworkDevices
    $value = if ($Enabled) { 1 } else { 0 }
    foreach ($d in $devices) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($d.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        if (Test-Path $path) {
            Backup-RegistryKey -KeyPath $path -BackupName "msi-net-$($d.InstanceId -replace '[\\\/]','_')" | Out-Null
            Set-RegValue -Path $path -Name 'MSISupported' -Value $value -Type DWord
        }
    }
    Write-EngineLog "MSI Mode reseau -> Enabled=$Enabled sur $(@($devices).Count) peripherique(s)" 'OK'
}

function Get-HandlerState_DnsFast {
    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue
    if (-not $adapters) { return 'unknown' }
    $allCloudflare = $true
    $any = $false
    foreach ($a in $adapters) {
        $current = Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if (-not $current -or -not $current.ServerAddresses -or $current.ServerAddresses.Count -eq 0) { continue }
        $any = $true
        if (($current.ServerAddresses | Sort-Object) -join ',' -ne '1.0.0.1,1.1.1.1') { $allCloudflare = $false }
    }
    if (-not $any) { return 'unknown' }
    if ($allCloudflare) { return 'on' }
    return 'off'
}

function Set-HandlerState_DnsFast {
    param([bool]$Enabled)
    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue
    if ($Enabled) {
        $captured = @()
        foreach ($a in $adapters) {
            $current = Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $captured += [PSCustomObject]@{ IfIndex = $a.ifIndex; OriginalServers = @($current.ServerAddresses) }
            try {
                Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses ('1.1.1.1','1.0.0.1') -ErrorAction SilentlyContinue
            } catch {
                Write-EngineLog "DNS rapide: echec sur $($a.Name): $($_.Exception.Message)" 'WARN'
            }
        }
        Save-EngineState 'dns-fast' $captured
        Write-EngineLog "DNS rapide (Cloudflare) applique sur $(@($adapters).Count) interface(s)" 'OK'
    } else {
        $state = Get-EngineState 'dns-fast'
        foreach ($a in $adapters) {
            $original = $null
            if ($state) { $original = ($state | Where-Object { $_.IfIndex -eq $a.ifIndex }).OriginalServers }
            try {
                if ($original -and @($original).Count -gt 0) {
                    Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $original -ErrorAction SilentlyContinue
                } else {
                    Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
                }
            } catch {
                Write-EngineLog "DNS restauration: echec sur $($a.Name): $($_.Exception.Message)" 'WARN'
            }
        }
        Write-EngineLog 'DNS restaure (DHCP/original)' 'OK'
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

function Get-HandlerState_StartMenuSuggestionsDisable {
    $v = Get-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SystemPaneSuggestionsEnabled'
    if ("$v" -eq '0') { return 'on' }
    return 'off'
}

function Set-HandlerState_StartMenuSuggestionsDisable {
    param([bool]$Enabled)
    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $names = @('SystemPaneSuggestionsEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled', 'RotatingLockScreenEnabled', 'RotatingLockScreenOverlayEnabled')
    if ($Enabled) {
        $captured = @{}
        foreach ($n in $names) { $captured[$n] = Get-RegValue -Path $path -Name $n }
        Save-EngineState 'start-menu-suggestions-disable' $captured
        foreach ($n in $names) { Set-RegValue -Path $path -Name $n -Value 0 -Type DWord }
    } else {
        $prev = Get-EngineState 'start-menu-suggestions-disable'
        foreach ($n in $names) {
            $restore = if ($prev -and $null -ne $prev.$n) { $prev.$n } else { 1 }
            Set-RegValue -Path $path -Name $n -Value $restore -Type DWord
        }
    }
    Write-EngineLog "Suggestions Start Menu/verrouillage -> Enabled(desactivees)=$Enabled" 'OK'
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
# Handlers nommes : Demarrage
# ============================================================

function Get-HandlerState_ShutdownTimeoutsReduce {
    $v = Get-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'HungAppTimeout'
    if ("$v" -eq '1000') { return 'on' }
    return 'off'
}

function Set-HandlerState_ShutdownTimeoutsReduce {
    param([bool]$Enabled)
    Backup-RegistryKey -KeyPath 'HKLM:\SYSTEM\CurrentControlSet\Control' -BackupName 'shutdown-timeouts-reduce-hklm' | Out-Null
    Backup-RegistryKey -KeyPath 'HKCU:\Control Panel\Desktop' -BackupName 'shutdown-timeouts-reduce-hkcu' | Out-Null
    if ($Enabled) {
        Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'WaitToKillServiceTimeout' -Value '2000' -Type String
        Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'HungAppTimeout' -Value '1000' -Type String
        Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WaitToKillAppTimeout' -Value '2000' -Type String
        Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'AutoEndTasks' -Value '1' -Type String
    } else {
        Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'WaitToKillServiceTimeout' -Value '5000' -Type String
        Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'HungAppTimeout' -Value '5000' -Type String
        Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WaitToKillAppTimeout' -Value '5000' -Type String
        Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'AutoEndTasks' -Value '0' -Type String
    }
    Write-EngineLog "Delais d'arret -> Enabled=$Enabled" 'OK'
}

function Get-HandlerState_SvchostSplitDynamic {
    $v = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'SvcHostSplitThresholdInKB'
    if ($null -eq $v) { return 'off' }
    return 'on'
}

function Set-HandlerState_SvchostSplitDynamic {
    param([bool]$Enabled)
    if ($Enabled) {
        $ramKb = [int64]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1KB)
        $threshold = [int64]($ramKb * 2)
        if ($threshold -gt [int32]::MaxValue) { $threshold = [int32]::MaxValue }
        Backup-RegistryKey -KeyPath 'HKLM:\SYSTEM\CurrentControlSet\Control' -BackupName 'svchost-split-dynamic' | Out-Null
        Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'SvcHostSplitThresholdInKB' -Value ([int32]$threshold) -Type DWord
        Write-EngineLog "SvcHostSplitThresholdInKB -> $threshold (RAM detectee: $ramKb KB, fusion forcee)" 'OK'
    } else {
        Remove-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'SvcHostSplitThresholdInKB'
        Write-EngineLog 'SvcHostSplitThresholdInKB retire (comportement Windows par defaut)' 'OK'
    }
}

# ============================================================
# Handlers nommes : Audio
# ============================================================

function Get-HandlerState_MmcssAudioPriority {
    $v = Get-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio' -Name 'Priority'
    if ("$v" -eq '8') { return 'on' }
    return 'off'
}

function Set-HandlerState_MmcssAudioPriority {
    param([bool]$Enabled)
    $audioPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio'
    $proAudioPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio'
    if ($Enabled) {
        foreach ($p in @($audioPath, $proAudioPath)) {
            Set-RegValue -Path $p -Name 'Priority' -Value 8 -Type DWord
            Set-RegValue -Path $p -Name 'Scheduling Category' -Value 'High' -Type String
            Set-RegValue -Path $p -Name 'SFIO Priority' -Value 'High' -Type String
        }
    } else {
        foreach ($p in @($audioPath, $proAudioPath)) {
            Set-RegValue -Path $p -Name 'Priority' -Value 6 -Type DWord
            Set-RegValue -Path $p -Name 'Scheduling Category' -Value 'Medium' -Type String
            Set-RegValue -Path $p -Name 'SFIO Priority' -Value 'Normal' -Type String
        }
    }
    Write-EngineLog "Priorite MMCSS Audio/Pro Audio -> Enabled=$Enabled" 'OK'
}

$Script:AudioRenderPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
$Script:PkeyFriendlyName = '{a45c254e-df1c-4efd-8020-67d146a850e0},14'
$Script:PkeyDisableSysFx = '{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5'

function Invoke-ListAudioDevices {
    $result = @()
    if (-not (Test-Path $Script:AudioRenderPath)) { return ,$result }
    $deviceKeys = Get-ChildItem -Path $Script:AudioRenderPath -ErrorAction SilentlyContinue
    foreach ($dk in $deviceKeys) {
        $guid = $dk.PSChildName
        $propsPath = Join-Path $dk.PSPath 'Properties'
        $name = Get-RegValue -Path $propsPath -Name $Script:PkeyFriendlyName
        if (-not $name) { $name = $guid }
        $fxPath = Join-Path $dk.PSPath 'FxProperties'
        $disabledVal = Get-RegValue -Path $fxPath -Name $Script:PkeyDisableSysFx
        $disabled = ("$disabledVal" -eq '1')
        $result += [PSCustomObject]@{ id = $guid; name = "$name"; enhancementsDisabled = $disabled }
    }
    return ,$result
}

function Invoke-SetAudioDeviceEffects {
    param($Payload)
    $fxPath = Join-Path $Script:AudioRenderPath "$($Payload.deviceId)\FxProperties"
    if (-not (Test-Path $fxPath)) { New-Item -Path $fxPath -Force | Out-Null }
    Backup-RegistryKey -KeyPath $fxPath -BackupName "audio-fx-$($Payload.deviceId)" | Out-Null
    $value = if ($Payload.disabled) { 1 } else { 0 }
    Set-RegValue -Path $fxPath -Name $Script:PkeyDisableSysFx -Value $value -Type DWord
    Write-EngineLog "Ameliorations audio peripherique $($Payload.deviceId) -> disabled=$($Payload.disabled)" 'OK'
}

# ============================================================
# Handlers nommes : Peripheriques
# ============================================================

function Get-HandlerState_MouseAccelerationDisable {
    $v = Get-RegValue -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed'
    if ("$v" -eq '0') { return 'on' }
    return 'off'
}

function Set-HandlerState_MouseAccelerationDisable {
    param([bool]$Enabled)
    $path = 'HKCU:\Control Panel\Mouse'
    if ($Enabled) {
        Set-RegValue -Path $path -Name 'MouseSpeed' -Value '0' -Type String
        Set-RegValue -Path $path -Name 'MouseThreshold1' -Value '0' -Type String
        Set-RegValue -Path $path -Name 'MouseThreshold2' -Value '0' -Type String
    } else {
        Set-RegValue -Path $path -Name 'MouseSpeed' -Value '1' -Type String
        Set-RegValue -Path $path -Name 'MouseThreshold1' -Value '6' -Type String
        Set-RegValue -Path $path -Name 'MouseThreshold2' -Value '10' -Type String
    }
    Write-EngineLog "Acceleration souris -> Enabled(desactivee)=$Enabled" 'OK'
}

function Get-HandlerState_UsbThreadPriority {
    $v = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\USBXHCI\Parameters' -Name 'ThreadPriority'
    if ("$v" -eq '31') { return 'on' }
    return 'off'
}

function Set-HandlerState_UsbThreadPriority {
    param([bool]$Enabled)
    $paths = @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\USBXHCI\Parameters',
        'HKLM:\SYSTEM\CurrentControlSet\Services\USBHUB3\Parameters'
    )
    foreach ($p in $paths) {
        if ($Enabled) {
            Set-RegValue -Path $p -Name 'ThreadPriority' -Value 31 -Type DWord
        } else {
            Remove-RegValue -Path $p -Name 'ThreadPriority'
        }
    }
    Write-EngineLog "Priorite des threads USB -> Enabled=$Enabled" 'OK'
}

function Get-HandlerState_CsrssPriority {
    $procs = Get-Process -Name 'csrss' -ErrorAction SilentlyContinue
    if (-not $procs) { return 'unknown' }
    $allHigh = $true
    foreach ($p in $procs) {
        try { if ($p.PriorityClass -ne [System.Diagnostics.ProcessPriorityClass]::High) { $allHigh = $false } }
        catch { $allHigh = $false }
    }
    if ($allHigh) { return 'on' }
    return 'off'
}

function Set-HandlerState_CsrssPriority {
    param([bool]$Enabled)
    $procs = Get-Process -Name 'csrss' -ErrorAction SilentlyContinue
    if (-not $procs) { throw 'Processus csrss.exe introuvable.' }
    $target = if ($Enabled) { [System.Diagnostics.ProcessPriorityClass]::High } else { [System.Diagnostics.ProcessPriorityClass]::Normal }
    $failures = 0
    foreach ($p in $procs) {
        try { $p.PriorityClass = $target } catch { $failures++ }
    }
    Start-Sleep -Milliseconds 200
    $verified = Get-HandlerState_CsrssPriority
    $expected = if ($Enabled) { 'on' } else { 'off' }
    if ($verified -ne $expected -or $failures -gt 0) {
        Write-EngineLog "Priorite csrss.exe: application demandee mais non confirmee (protection PPL probable, $failures echec(s))" 'WARN'
        throw 'La modification de priorite de csrss.exe a ete refusee par Windows (Protected Process Light). Ce mecanisme herite ne fonctionne plus de facon fiable sur les versions modernes.'
    }
    Write-EngineLog "Priorite csrss.exe -> Enabled=$Enabled (verifiee)" 'OK'
}

# ============================================================
# Handlers nommes : Latence
# ============================================================

function Get-HandlerState_DynamicTickDisable {
    $state = Get-EngineState 'dynamic-tick-disable'
    if ($state -and $state.applied) { return 'on' }
    return 'off'
}

function Set-HandlerState_DynamicTickDisable {
    param([bool]$Enabled)
    if ($Enabled) {
        & bcdedit /set '{current}' disabledynamictick yes | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'bcdedit a refuse la modification de disabledynamictick (droits administrateur requis ?).' }
    } else {
        & bcdedit /deletevalue '{current}' disabledynamictick 2>&1 | Out-Null
    }
    Save-EngineState 'dynamic-tick-disable' @{ applied = $Enabled }
    Write-EngineLog "Dynamic Tick desactive -> Enabled=$Enabled (effectif au prochain redemarrage)" 'OK'
}

function Get-HandlerState_TscSyncPolicyEnhanced {
    $state = Get-EngineState 'tsc-sync-policy-enhanced'
    if ($state -and $state.applied) { return 'on' }
    return 'off'
}

function Set-HandlerState_TscSyncPolicyEnhanced {
    param([bool]$Enabled)
    if ($Enabled) {
        & bcdedit /set '{current}' tscsyncpolicy Enhanced | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'bcdedit a refuse la modification de tscsyncpolicy (droits administrateur requis ?).' }
    } else {
        & bcdedit /deletevalue '{current}' tscsyncpolicy 2>&1 | Out-Null
    }
    Save-EngineState 'tsc-sync-policy-enhanced' @{ applied = $Enabled }
    Write-EngineLog "TSC Sync Policy Enhanced -> Enabled=$Enabled (effectif au prochain redemarrage)" 'OK'
}

function Get-HandlerState_HpetDisable {
    $state = Get-EngineState 'hpet-disable'
    if ($state -and $state.applied) { return 'on' }
    return 'off'
}

function Set-HandlerState_HpetDisable {
    param([bool]$Enabled)
    & bcdedit /deletevalue '{current}' useplatformclock 2>&1 | Out-Null
    Save-EngineState 'hpet-disable' @{ applied = $Enabled }
    Write-EngineLog "HPET (useplatformclock) -> desactive=$Enabled (effectif au prochain redemarrage)" 'OK'
}

function Get-GpuIrqNumber {
    $gpu = Get-CimInstance Win32_PNPAllocatedResource -ErrorAction SilentlyContinue | Where-Object {
        $_.Antecedent -match 'Win32_IRQResource' -and $_.Dependent -match 'Win32_PNPEntity'
    }
    $displayDevices = Get-PnpDevice -Class Display -Status OK -ErrorAction SilentlyContinue
    foreach ($d in $displayDevices) {
        $match = $gpu | Where-Object { $_.Dependent -match [regex]::Escape($d.DeviceID) }
        if ($match) {
            $irqMatch = [regex]::Match($match.Antecedent, 'IRQNumber="(\d+)"')
            if ($irqMatch.Success) { return [int]$irqMatch.Groups[1].Value }
        }
    }
    return $null
}

function Get-HandlerState_IrqPriorityTuning {
    $v = Get-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'IRQ8Priority'
    if ("$v" -eq '1') { return 'on' }
    return 'off'
}

function Set-HandlerState_IrqPriorityTuning {
    param([bool]$Enabled)
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'
    if ($Enabled) {
        Backup-RegistryKey -KeyPath $path -BackupName 'irq-priority-tuning' | Out-Null
        Set-RegValue -Path $path -Name 'IRQ8Priority' -Value 1 -Type DWord
        $gpuIrq = Get-GpuIrqNumber
        if ($gpuIrq) {
            Set-RegValue -Path $path -Name "IRQ${gpuIrq}Priority" -Value 2 -Type DWord
            Save-EngineState 'irq-priority-tuning' @{ gpuIrq = $gpuIrq }
            Write-EngineLog "Priorite IRQ8 (horloge) + IRQ$gpuIrq (GPU detecte) appliquee" 'OK'
        } else {
            Save-EngineState 'irq-priority-tuning' @{ gpuIrq = $null }
            Write-EngineLog 'Priorite IRQ8 appliquee ; IRQ GPU non detecte (MSI Mode actif ?), ignore' 'WARN'
        }
    } else {
        Remove-RegValue -Path $path -Name 'IRQ8Priority'
        $state = Get-EngineState 'irq-priority-tuning'
        if ($state -and $state.gpuIrq) {
            Remove-RegValue -Path $path -Name "IRQ$($state.gpuIrq)Priority"
        }
        Write-EngineLog 'Priorite IRQ retiree' 'OK'
    }
}

# ============================================================
# Handlers nommes : Productivite
# ============================================================

function Get-HandlerState_TaskbarMultiMonitorShowAll {
    $v = Get-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'MMTaskbarEnabled'
    if ("$v" -eq '1') { return 'on' }
    return 'off'
}

function Set-HandlerState_TaskbarMultiMonitorShowAll {
    param([bool]$Enabled)
    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    if ($Enabled) {
        Set-RegValue -Path $path -Name 'MMTaskbarEnabled' -Value 1 -Type DWord
        Set-RegValue -Path $path -Name 'MMTaskbarMode' -Value 0 -Type DWord
        Set-RegValue -Path $path -Name 'MMTaskbarGlomLevel' -Value 0 -Type DWord
    } else {
        Set-RegValue -Path $path -Name 'MMTaskbarEnabled' -Value 0 -Type DWord
        Set-RegValue -Path $path -Name 'MMTaskbarMode' -Value 0 -Type DWord
        Set-RegValue -Path $path -Name 'MMTaskbarGlomLevel' -Value 0 -Type DWord
    }
    Write-EngineLog "Barre des taches multi-ecrans -> Enabled=$Enabled" 'OK'
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

$Script:AppCompatLayersPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$Script:FullscreenOptFlag = 'DISABLEDXMAXIMIZEDWINDOWEDMODE'

function Invoke-ListFullscreenOptApps {
    $result = @()
    if (Test-Path $Script:AppCompatLayersPath) {
        $props = Get-ItemProperty -Path $Script:AppCompatLayersPath -ErrorAction SilentlyContinue
        if ($props) {
            foreach ($prop in $props.PSObject.Properties) {
                if ($prop.Name -like 'PS*') { continue }
                if ("$($prop.Value)" -match [regex]::Escape($Script:FullscreenOptFlag)) {
                    $result += [PSCustomObject]@{ path = $prop.Name }
                }
            }
        }
    }
    return ,$result
}

function Invoke-AddFullscreenOptApp {
    param($Payload)
    if (-not (Test-Path $Script:AppCompatLayersPath)) { New-Item -Path $Script:AppCompatLayersPath -Force | Out-Null }
    $existing = Get-RegValue -Path $Script:AppCompatLayersPath -Name $Payload.path
    $flags = if ($existing) { "$existing" } else { '~' }
    if ($flags -notmatch [regex]::Escape($Script:FullscreenOptFlag)) {
        $flags = "$flags $($Script:FullscreenOptFlag)".Trim()
    }
    Set-RegValue -Path $Script:AppCompatLayersPath -Name $Payload.path -Value $flags -Type String
    Write-EngineLog "Optimisations plein ecran desactivees: $($Payload.path)" 'OK'
}

function Invoke-RemoveFullscreenOptApp {
    param($Payload)
    $existing = Get-RegValue -Path $Script:AppCompatLayersPath -Name $Payload.path
    if (-not $existing) { return }
    $remaining = (($existing -split '\s+') | Where-Object { $_ -and $_ -ne $Script:FullscreenOptFlag -and $_ -ne '~' }) -join ' '
    if ($remaining) {
        Set-RegValue -Path $Script:AppCompatLayersPath -Name $Payload.path -Value "~ $remaining" -Type String
    } else {
        Remove-RegValue -Path $Script:AppCompatLayersPath -Name $Payload.path
    }
    Write-EngineLog "Optimisations plein ecran reactivees: $($Payload.path)" 'OK'
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
        if ($entry.guardRequiresDeviceClass) {
            $guardOk = $guardOk -and (Test-DeviceClassPresent -ClassName $entry.guardRequiresDeviceClass)
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
        'ListFullscreenOptApps' { Invoke-ListFullscreenOptApps }
        'AddFullscreenOptApp' { Invoke-AddFullscreenOptApp -Payload $Script:Payload; $null }
        'RemoveFullscreenOptApp' { Invoke-RemoveFullscreenOptApp -Payload $Script:Payload; $null }
        'ListAudioDevices' { Invoke-ListAudioDevices }
        'SetAudioDeviceEffects' { Invoke-SetAudioDeviceEffects -Payload $Script:Payload; $null }
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
