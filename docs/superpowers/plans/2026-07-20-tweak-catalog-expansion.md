# Extension du catalogue de tweaks (Chantier 1) — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Étendre `data/tweaks-catalog.json` de 22 à 61 entrées (39 nouveaux tweaks automatisés + 2 listes dynamiques déjà existantes conservées), en ajoutant 4 nouvelles catégories (`audio`, `peripheriques`, `latence`, `productivite`), un nouveau champ de schéma `guardRequiresDeviceClass`, et 2 nouveaux widgets de liste spéciale (`audio-device-list`, `fullscreen-opt-list`), conformément à `docs/superpowers/specs/2026-07-20-tweak-catalog-expansion-design.md`.

**Architecture:** Le moteur (`engine/Engine.ps1`) garde son dispatcher générique existant (`Get-ToggleState`/`Set-ToggleValue`/`Get-DefaultEnabled`) pour tous les tweaks `kind: registry|service|handler` — la plupart des nouveaux tweaks n'ajoutent que des entrées JSON (registry/service) ou une paire de fonctions `Get-HandlerState_X`/`Set-HandlerState_X` (handler), sans toucher au dispatcher. Les 2 tweaks à état multi-instance (`audio-enhancements-disable`, `fullscreen-optimizations-disable`) suivent le motif existant des listes spéciales sans `kind` (`type` dédié + actions `Invoke-List*`/`Invoke-Add*`/`Invoke-Remove*`/`Invoke-Set*` + fonction `render*` côté UI), sur le modèle de `exe-list`/`renderGpuPrefList` déjà en place.

**Tech Stack:** Electron (renderer vanilla JS, `renderer/app.js`), moteur PowerShell (`engine/Engine.ps1`, `engine/Common.ps1`), catalogue piloté par données (`data/tweaks-catalog.json`). Pas de framework de test dans le projet : la vérification se fait par contrôle de syntaxe (`ParseFile` PowerShell, `node --check`, `JSON.parse`) puis vérification manuelle via `npm start`.

---

## Conventions communes à toutes les tâches

- Chaque nouvelle entrée JSON s'insère dans le tableau top-niveau de `data/tweaks-catalog.json`, **immédiatement avant le `]` final qui ferme le tableau** (ajouter une virgule après la dernière entrée existante).
- Après CHAQUE tâche touchant `engine/Engine.ps1`, vérifier la syntaxe avec :
  ```
  powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'engine/Engine.ps1'), [ref]$null, [ref]$null); Write-Host 'Syntaxe OK'"
  ```
  Expected: `Syntaxe OK` (aucune exception levée).
- Après CHAQUE tâche touchant `data/tweaks-catalog.json`, vérifier le JSON avec :
  ```
  node -e "JSON.parse(require('fs').readFileSync('data/tweaks-catalog.json','utf8')); console.log('JSON OK')"
  ```
  Expected: `JSON OK`.
- Après CHAQUE tâche touchant `renderer/app.js`, vérifier la syntaxe avec :
  ```
  node --check renderer/app.js
  ```
  Expected: aucune sortie (code de sortie 0).
- Toutes les nouvelles fonctions PowerShell s'ajoutent à la fin de la section `# ============================================================` correspondante dans `engine/Engine.ps1`, ou dans une nouvelle section si la catégorie est nouvelle (ajoutée juste avant `# Listes dynamiques : demarrage, debloat, preference GPU` autour de la ligne 450).
- Commit après chaque tâche (voir commande exacte dans chaque tâche).

---

### Task 1 : Champ de schéma `guardRequiresDeviceClass` (moteur + UI)

Garde positive symétrique de `guardNoDeviceClass` existant : le tweak n'est activable/visible que si la classe de périphérique **est présente** (au lieu de bloqué quand elle l'est). Utilisé par `windows-recall-disable` (Task 7) pour ne l'afficher que si un NPU est détecté (`Get-PnpDevice -Class 'ComputeAccelerator'`).

**Files:**
- Modify: `engine/Engine.ps1:585-597` (`Invoke-GetAllStates`)
- Modify: `renderer/app.js:51-59` (`categoryCounts`)
- Modify: `renderer/app.js:214-257` (`renderCategoryPage`)

- [x] **Step 1 : Étendre `Invoke-GetAllStates` pour calculer la garde positive**

Dans `engine/Engine.ps1`, remplacer :

```powershell
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
```

par :

```powershell
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
```

- [x] **Step 2 : Vérifier la syntaxe PowerShell**

Run: `powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'engine/Engine.ps1'), [ref]$null, [ref]$null); Write-Host 'Syntaxe OK'"`
Expected: `Syntaxe OK`

- [x] **Step 3 : Filtrer l'affichage dans `renderCategoryPage` (masquer si garde positive échoue)**

Dans `renderer/app.js`, remplacer la ligne :

```javascript
    toggleEntriesForCategory(cat).forEach((entry) => renderToggleCard(entry));
```

par :

```javascript
    toggleEntriesForCategory(cat).forEach((entry) => {
      if (entry.guardRequiresDeviceClass) {
        const s = state.statesById[entry.id];
        if (s && !s.guardOk) return;
      }
      renderToggleCard(entry);
    });
```

- [x] **Step 4 : Exclure ces entrées masquées du compte de la sidebar/dashboard**

Dans `renderer/app.js`, remplacer :

```javascript
  function categoryCounts(cat) {
    const entries = toggleEntriesForCategory(cat);
    let on = 0;
    entries.forEach((e) => {
      const eff = effectiveState(e.id);
      if (eff === 'on') on++;
    });
    return { on, total: entries.length };
  }
```

par :

```javascript
  function categoryCounts(cat) {
    const entries = toggleEntriesForCategory(cat).filter((e) => {
      if (!e.guardRequiresDeviceClass) return true;
      const s = state.statesById[e.id];
      return s ? s.guardOk : true;
    });
    let on = 0;
    entries.forEach((e) => {
      const eff = effectiveState(e.id);
      if (eff === 'on') on++;
    });
    return { on, total: entries.length };
  }
```

- [x] **Step 5 : Vérifier la syntaxe JS**

Run: `node --check renderer/app.js`
Expected: aucune sortie, code de sortie 0.

- [x] **Step 6 : Commit**

```
git add engine/Engine.ps1 renderer/app.js
git commit -m "Ajouter le champ de schema guardRequiresDeviceClass (garde positive)"
```

**Statut d'execution : DONE.** Implemente par subagent (commit `bc22242`). Spec-compliant (revue independante) et code-quality "approved with follow-ups" (2 remarques mineures non bloquantes : logique de filtre dupliquee sous 2 formes differentes entre `categoryCounts`/`renderCategoryPage`, et le bouton "Redemarrer l'Explorateur" n'est pas filtre par `guardOk` — sans impact car aucune entree Task 7 ne combine `guardRequiresDeviceClass` et `requiresExplorerRestart`).

---

### Task 2 : Catégorie Alimentation — `cpu-boost-aggressive`

**Files:**
- Modify: `data/tweaks-catalog.json` (ajouter 1 entrée)
- Modify: `engine/Engine.ps1` (ajouter 2 fonctions, section "Handlers nommes : Plans d'alimentation")

- [x] **Step 1 : Ajouter l'entrée catalogue**

Insérer avant le `]` final de `data/tweaks-catalog.json` (après avoir ajouté une virgule à la fin de la dernière entrée existante, `mmcss-tuning`) :

```json
  ,
  {
    "id": "cpu-boost-aggressive",
    "category": "alimentation",
    "risk": "avance",
    "type": "toggle",
    "kind": "handler",
    "handler": "CpuBoostAggressive",
    "requiresRestart": false,
    "label": "Mode Boost Processeur agressif",
    "description": "Force le CPU à privilégier la fréquence maximale plus tôt (mode Aggressive du Processor Performance Boost). Augmente la consommation et la chaleur, surtout sur portable."
  }
```

- [x] **Step 2 : Ajouter les fonctions handler dans `engine/Engine.ps1`**

Ajouter à la fin de la section `# Handlers nommes : Plans d'alimentation` (juste avant `# ============================================================` qui introduit `# Handlers nommes : Reseau`, autour de la ligne 173) :

```powershell
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
```

(Motif identique à `Get/Set-HandlerState_UsbSelectiveSuspend` déjà présent juste au-dessus — GUID `SUB_PROCESSOR`/`PERFBOOSTMODE` documentés par Microsoft, valeur `2` = Aggressive.)

- [x] **Step 3 : Vérifier**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/tweaks-catalog.json','utf8')); console.log('JSON OK')"` → `JSON OK`
Run: `powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'engine/Engine.ps1'), [ref]$null, [ref]$null); Write-Host 'Syntaxe OK'"` → `Syntaxe OK`

- [x] **Step 4 : Commit**

```
git add data/tweaks-catalog.json engine/Engine.ps1
git commit -m "Ajouter le tweak cpu-boost-aggressive (categorie Alimentation)"
```

**Statut d'execution : DONE.** Implemente par subagent (commit `9179de8`). Spec-compliant (revue independante : entree catalogue et fonctions handler conformes caractere pour caractere). Code-quality "approved with follow-ups" (aucun probleme critique ; remarques mineures non bloquantes : la lecture d'etat ne verifie que la valeur AC, pas DC — defaut deja present dans `Get-HandlerState_UsbSelectiveSuspend` dont ce handler s'inspire ; style de virgule JSON legerement different du reste du fichier ; les 2 constantes GUID ne sont pas regroupees avec les autres constantes de la section — toutes conformes au plan tel qu'ecrit).

---

### Task 3 : Catégorie Réseau — 6 tweaks

**Files:**
- Modify: `data/tweaks-catalog.json` (ajouter 6 entrées)
- Modify: `engine/Engine.ps1` (ajouter 8 fonctions, section "Handlers nommes : Reseau")

- [x] **Step 1 : Ajouter les 6 entrées catalogue**

Insérer avant le `]` final :

```json
  ,
  {
    "id": "network-throttling-unlimited",
    "category": "reseau",
    "risk": "intermediaire",
    "type": "toggle",
    "kind": "registry",
    "path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile",
    "name": "NetworkThrottlingIndex",
    "regType": "DWord",
    "onValue": -1,
    "offValue": 10,
    "defaultValue": 10,
    "requiresRestart": false,
    "label": "Suppression de la limitation réseau multimédia",
    "description": "Supprime la limitation à environ 80% de bande passante que Windows applique au trafic réseau non-multimédia quand une application audio/vidéo tourne (NetworkThrottlingIndex). Utile en streaming/partage d'écran pendant le jeu."
  },
  {
    "id": "network-ipv6-disable",
    "category": "reseau",
    "risk": "intermediaire",
    "type": "toggle",
    "kind": "handler",
    "handler": "NetworkIPv6Disable",
    "requiresRestart": false,
    "label": "Désactiver IPv6",
    "description": "Désactive le protocole IPv6 sur toutes les interfaces physiques. Peut casser des services qui dépendent explicitement d'IPv6."
  },
  {
    "id": "delivery-optimization-http-only",
    "category": "reseau",
    "risk": "basique",
    "type": "toggle",
    "kind": "registry",
    "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DeliveryOptimization",
    "name": "DODownloadMode",
    "regType": "DWord",
    "onValue": 0,
    "offValue": null,
    "defaultValue": null,
    "requiresRestart": false,
    "label": "Delivery Optimization en HTTP seul",
    "description": "Empêche Windows Update de partager/télécharger des mises à jour en pair-à-pair (LAN ou Internet). Tout le trafic de mise à jour passe uniquement par les serveurs Microsoft."
  },
  {
    "id": "network-power-management-disable",
    "category": "reseau",
    "risk": "basique",
    "type": "toggle",
    "kind": "handler",
    "handler": "NetworkPowerManagementDisable",
    "requiresRestart": false,
    "label": "Désactiver la gestion d'énergie de la carte réseau",
    "description": "Empêche Windows de mettre en veille la carte réseau pour économiser l'énergie (case \"Autoriser l'ordinateur à éteindre ce périphérique\" décochée sur toutes les interfaces)."
  },
  {
    "id": "msi-mode-network",
    "category": "reseau",
    "risk": "intermediaire",
    "type": "toggle",
    "kind": "handler",
    "handler": "MsiModeNetwork",
    "requiresRestart": true,
    "label": "MSI Mode (contrôleurs réseau)",
    "description": "Extension du MSI Mode (interruptions matérielles en mode Message Signaled) aux contrôleurs réseau, même mécanisme que le MSI Mode GPU/USB existant mais ciblant la classe de périphérique Réseau."
  },
  {
    "id": "dns-fast",
    "category": "reseau",
    "risk": "basique",
    "type": "toggle",
    "kind": "handler",
    "handler": "DnsFast",
    "requiresRestart": false,
    "label": "Basculer vers un résolveur DNS rapide (Cloudflare)",
    "description": "Configure 1.1.1.1 / 1.0.0.1 (Cloudflare) comme serveurs DNS sur toutes les interfaces physiques, à la place du DNS fourni par ton FAI/routeur. L'état DNS d'origine est sauvegardé pour un rollback exact."
  }
```

- [x] **Step 2 : Ajouter les fonctions handler dans `engine/Engine.ps1`**

Ajouter à la fin de la section `# Handlers nommes : Reseau` (juste avant `# ============================================================` qui introduit `# Handlers nommes : Affichage`, autour de la ligne 254) :

```powershell
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
    $adapters = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' }
    if (-not $adapters) { return 'unknown' }
    $allCloudflare = $true
    $any = $false
    foreach ($a in $adapters) {
        if (-not $a.ServerAddresses -or $a.ServerAddresses.Count -eq 0) { continue }
        $any = $true
        if (($a.ServerAddresses -join ',') -ne '1.1.1.1,1.0.0.1') { $allCloudflare = $false }
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
            Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses ('1.1.1.1','1.0.0.1') -ErrorAction SilentlyContinue
        }
        Save-EngineState 'dns-fast' $captured
        Write-EngineLog "DNS rapide (Cloudflare) applique sur $(@($adapters).Count) interface(s)" 'OK'
    } else {
        $state = Get-EngineState 'dns-fast'
        foreach ($a in $adapters) {
            $original = $null
            if ($state) { $original = ($state | Where-Object { $_.IfIndex -eq $a.ifIndex }).OriginalServers }
            if ($original -and @($original).Count -gt 0) {
                Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $original -ErrorAction SilentlyContinue
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
            }
        }
        Write-EngineLog 'DNS restaure (DHCP/original)' 'OK'
    }
}
```

Note : `network-throttling-unlimited` et `delivery-optimization-http-only` sont `kind: registry` — aucune fonction moteur nécessaire, le dispatcher générique `Get-ToggleState`/`Set-ToggleValue` les gère directement à partir de leur JSON.

- [x] **Step 3 : Vérifier**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/tweaks-catalog.json','utf8')); console.log('JSON OK')"` → `JSON OK`
Run: `powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'engine/Engine.ps1'), [ref]$null, [ref]$null); Write-Host 'Syntaxe OK'"` → `Syntaxe OK`

- [x] **Step 4 : Commit**

```
git add data/tweaks-catalog.json engine/Engine.ps1
git commit -m "Ajouter 6 tweaks reseau (throttling, IPv6, delivery optimization, power mgmt, MSI, DNS)"
```

**Statut d'execution : DONE.** Implemente par subagent (commit `1837adc`). Spec-compliant (revue independante : les 6 entrees catalogue et les 9 fonctions handler — 4 paires Get/Set + 1 helper `Get-MsiTargetNetworkDevices` — conformes caractere pour caractere ; note du plan corrigee de "8 fonctions" a "9 fonctions"). Code-quality "approved with follow-ups" a d'abord releve 2 points Importants dans `dns-fast` : (1) `Get-HandlerState_DnsFast` interrogeait toutes les interfaces IPv4 non-loopback (y compris VPN/Hyper-V/WSL) alors que `Set-HandlerState_DnsFast` ne modifiait que les interfaces physiques, causant un etat incoherent sur les machines avec adaptateurs virtuels ; (2) `Set-HandlerState_DnsFast` n'avait pas de `try/catch`+log WARN par interface contrairement aux handlers reseau voisins. Ces 2 points ont ete corriges immediatement (commit `9841d5e`) : `Get-HandlerState_DnsFast` s'aligne desormais sur `Get-NetAdapter -Physical` comme `Set-HandlerState_DnsFast`, la comparaison des serveurs DNS est desormais insensible a l'ordre (`Sort-Object`), et les echecs de `Set-DnsClientServerAddress` sont journalises en WARN dans les deux branches (activation/restauration). Verifie syntaxiquement OK apres correctif.

---

### Task 4 : Catégorie Affichage/Jeux — 2 registry + 1 liste spéciale (`fullscreen-opt-list`)

**Files:**
- Modify: `data/tweaks-catalog.json` (ajouter 3 entrées)
- Modify: `engine/Engine.ps1` (3 nouvelles actions `Invoke-*FullscreenOptApp*` + dispatch)
- Modify: `renderer/app.js` (dispatch `renderSpecialWidget` + fonction `renderFullscreenOptList`)

- [x] **Step 1 : Ajouter les 3 entrées catalogue**

Insérer avant le `]` final :

```json
  ,
  {
    "id": "tdr-delay-increase",
    "category": "affichage",
    "risk": "avance",
    "type": "toggle",
    "kind": "registry",
    "path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\GraphicsDrivers",
    "name": "TdrDelay",
    "regType": "DWord",
    "onValue": 8,
    "offValue": null,
    "defaultValue": null,
    "requiresRestart": true,
    "label": "Augmenter le délai TDR (Timeout Detection and Recovery)",
    "description": "Passe de 2 à 8 secondes le délai avant que Windows considère le driver GPU comme figé et le redémarre. Réduit les faux TDR sur overclock GPU agressif. Microsoft déconseille cette clé aux utilisateurs finaux : si ton driver plante vraiment, l'écran restera figé plus longtemps avant récupération."
  },
  {
    "id": "gpu-preemption-disable",
    "category": "affichage",
    "risk": "avance",
    "type": "toggle",
    "kind": "registry",
    "path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\GraphicsDrivers\\Scheduler",
    "name": "EnablePreemption",
    "regType": "DWord",
    "onValue": 0,
    "offValue": 1,
    "defaultValue": 1,
    "requiresRestart": true,
    "label": "Désactiver la préemption GPU",
    "description": "Empêche le GPU d'interrompre une tâche de rendu en cours pour en prioriser une autre. Mécanisme recoupé sur plusieurs sources communautaires mais non documenté officiellement par Microsoft : effet non garanti selon la configuration."
  },
  {
    "id": "fullscreen-optimizations-disable",
    "category": "jeux",
    "risk": "intermediaire",
    "type": "fullscreen-opt-list",
    "requiresRestart": false,
    "label": "Désactiver les optimisations plein écran par jeu",
    "description": "Force le jeu choisi à utiliser le vrai mode plein écran exclusif (DX9-11) au lieu du \"plein écran optimisé\" de Windows, qui ajoute parfois de la latence d'affichage."
  }
```

- [x] **Step 2 : Ajouter les actions moteur pour `fullscreen-opt-list` dans `engine/Engine.ps1`**

Ajouter juste après la fonction `Invoke-RemoveGpuPrefApp` (avant `# ============================================================` / `# Points de restauration`, autour de la ligne 554) :

```powershell
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
```

- [x] **Step 3 : Câbler les 3 nouvelles actions dans le dispatch principal**

Dans `engine/Engine.ps1`, dans le bloc `switch ($Action)` de la fonction de dispatch (autour de la ligne 641), ajouter ces 3 lignes juste après `'RemoveGpuPrefApp' { Invoke-RemoveGpuPrefApp -Payload $Script:Payload; $null }` :

```powershell
        'ListFullscreenOptApps' { Invoke-ListFullscreenOptApps }
        'AddFullscreenOptApp' { Invoke-AddFullscreenOptApp -Payload $Script:Payload; $null }
        'RemoveFullscreenOptApp' { Invoke-RemoveFullscreenOptApp -Payload $Script:Payload; $null }
```

- [x] **Step 4 : Ajouter le rendu UI dans `renderer/app.js`**

Remplacer la ligne (autour de la ligne 346) :

```javascript
    if (entry.type === 'exe-list') return renderGpuPrefList(entry);
```

par :

```javascript
    if (entry.type === 'exe-list') return renderGpuPrefList(entry);
    if (entry.type === 'fullscreen-opt-list') return renderFullscreenOptList(entry);
```

Puis ajouter la fonction `renderFullscreenOptList` juste après `renderGpuPrefList` (après la ligne 482, avant `function renderGuide()`) :

```javascript
  async function renderFullscreenOptList(entry) {
    sectionTitle(entry.label);
    const wrapper = document.createElement('div');
    contentEl.appendChild(wrapper);
    const listHolder = document.createElement('div');
    wrapper.appendChild(listHolder);

    const addBtn = document.createElement('button');
    addBtn.className = 'btn';
    addBtn.textContent = 'Ajouter un executable...';
    addBtn.addEventListener('click', async () => {
      const picked = await window.api.pickExecutable();
      if (!picked.ok) return;
      const r = await window.api.callEngine('AddFullscreenOptApp', { path: picked.path });
      if (!r.ok) { toast('Echec: ' + r.error, false); return; }
      await load();
    });
    wrapper.appendChild(addBtn);

    async function load() {
      listHolder.innerHTML = '<div class="spinner-note">Chargement...</div>';
      const res = await window.api.callEngine('ListFullscreenOptApps');
      listHolder.innerHTML = '';
      if (!res.ok) { listHolder.innerHTML = `<div class="empty-state">${res.error}</div>`; return; }
      if (!res.data || !res.data.length) { listHolder.innerHTML = '<div class="empty-state">Aucun executable configure.</div>'; return; }
      res.data.forEach((item) => {
        const row = document.createElement('div');
        row.className = 'list-row';
        const main = document.createElement('div');
        main.className = 'list-row-main';
        main.innerHTML = `<div class="list-row-sub" title="${item.path}">${item.path}</div>`;
        row.appendChild(main);
        const btn = document.createElement('button');
        btn.className = 'btn btn-ghost';
        btn.textContent = 'Retirer';
        btn.addEventListener('click', async () => {
          const r = await window.api.callEngine('RemoveFullscreenOptApp', { path: item.path });
          if (!r.ok) { toast('Echec: ' + r.error, false); return; }
          await load();
        });
        row.appendChild(btn);
        listHolder.appendChild(row);
      });
    }
    await load();
  }
```

- [x] **Step 5 : Vérifier**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/tweaks-catalog.json','utf8')); console.log('JSON OK')"` → `JSON OK`
Run: `powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'engine/Engine.ps1'), [ref]$null, [ref]$null); Write-Host 'Syntaxe OK'"` → `Syntaxe OK`
Run: `node --check renderer/app.js` → aucune sortie

- [x] **Step 6 : Commit**

```
git add data/tweaks-catalog.json engine/Engine.ps1 renderer/app.js
git commit -m "Ajouter tdr-delay-increase, gpu-preemption-disable et la liste fullscreen-opt-list"
```

**Statut d'execution : DONE.** Implemente par subagent (commit `c3747df`). Spec-compliant (revue independante : 3 entrees catalogue, 3 fonctions `Invoke-*FullscreenOptApp*` + 2 variables script, 3 lignes de dispatch switch, et le rendu UI `renderFullscreenOptList` conformes caractere pour caractere ; seul ecart note : une virgule finale cosmetique corrigee au passage sur l'entree `cpu-boost-aggressive` preexistante, sans impact). Code-quality "approved with follow-ups" (aucun probleme bloquant) : la logique de manipulation des flags AppCompat (ajout/retrait de `DISABLEDXMAXIMIZEDWINDOWEDMODE` dans une valeur multi-flags) a ete verifiee robuste face a la coexistence avec d'autres flags (`RUNASADMIN`, `HIGHDPIAWARE`) deja presents sur le meme executable ; seule remarque mineure : `renderFullscreenOptList` est une duplication quasi exacte de `renderGpuPrefList`, candidate a factorisation future mais non bloquante et coherente avec le niveau de duplication deja tolere ailleurs dans le fichier.

---

### Task 5 : Catégorie Démarrage — 5 tweaks

**Files:**
- Modify: `data/tweaks-catalog.json` (ajouter 5 entrées)
- Modify: `engine/Engine.ps1` (ajouter 4 fonctions ; `searchindexer-priority-reduce`/`tiworker-priority-reduce` sont `kind: registry`, aucune fonction requise)

- [x] **Step 1 : Ajouter les 5 entrées catalogue**

Insérer avant le `]` final :

```json
  ,
  {
    "id": "fast-startup-disable",
    "category": "demarrage",
    "risk": "basique",
    "type": "toggle",
    "kind": "registry",
    "path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Power",
    "name": "HiberbootEnabled",
    "regType": "DWord",
    "onValue": 0,
    "offValue": 1,
    "defaultValue": 1,
    "requiresRestart": true,
    "label": "Désactiver le Démarrage rapide",
    "description": "Coupe l'hibernation partielle du noyau au démarrage (Fast Startup). Utile si tu dual-boot ou si des périphériques ne s'initialisent pas correctement après un arrêt."
  },
  {
    "id": "shutdown-timeouts-reduce",
    "category": "demarrage",
    "risk": "basique",
    "type": "toggle",
    "kind": "handler",
    "handler": "ShutdownTimeoutsReduce",
    "requiresRestart": false,
    "label": "Réduire les délais d'arrêt",
    "description": "Réduit les délais que Windows attend avant de forcer la fermeture des services et applications qui ne répondent plus à l'arrêt/redémarrage."
  },
  {
    "id": "svchost-split-dynamic",
    "category": "demarrage",
    "risk": "avance",
    "type": "toggle",
    "kind": "handler",
    "handler": "SvchostSplitDynamic",
    "requiresRestart": true,
    "label": "Fusion intelligente des processus svchost",
    "description": "Calcule dynamiquement un seuil (2x la RAM détectée) pour forcer Windows à regrouper les services dans moins de processus svchost.exe, réduisant l'overhead mémoire. Sans effet visible si peu de RAM est installée."
  },
  {
    "id": "searchindexer-priority-reduce",
    "category": "demarrage",
    "risk": "avance",
    "type": "toggle",
    "kind": "registry",
    "path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution Options\\SearchIndexer.exe\\PerfOptions",
    "name": "CpuPriorityClass",
    "regType": "DWord",
    "onValue": 1,
    "offValue": null,
    "defaultValue": null,
    "requiresRestart": false,
    "label": "Priorité CPU réduite pour SearchIndexer.exe",
    "description": "Force la priorité CPU du processus d'indexation Windows Search à \"Faible\" (Idle), sans désactiver l'indexation elle-même. Réduit son impact pendant les sessions de jeu."
  },
  {
    "id": "tiworker-priority-reduce",
    "category": "demarrage",
    "risk": "avance",
    "type": "toggle",
    "kind": "registry",
    "path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Image File Execution Options\\TiWorker.exe\\PerfOptions",
    "name": "CpuPriorityClass",
    "regType": "DWord",
    "onValue": 1,
    "offValue": null,
    "defaultValue": null,
    "requiresRestart": false,
    "label": "Priorité CPU réduite pour TiWorker.exe",
    "description": "Force la priorité CPU du worker Windows Update (TiWorker.exe, souvent responsable de pics CPU en arrière-plan) à \"Faible\", sans bloquer les mises à jour elles-mêmes."
  }
```

- [x] **Step 2 : Ajouter une nouvelle section de handlers dans `engine/Engine.ps1`**

Ajouter une nouvelle section juste avant `# ============================================================` / `# Listes dynamiques : demarrage, debloat, preference GPU` (autour de la ligne 449) :

```powershell
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
    $ramKb = [int64]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1KB)
    if ([int64]$v -gt $ramKb) { return 'on' }
    return 'off'
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
```

Remarque sur `SvchostSplitDynamic` : le seuil est plafonné à `[int32]::MaxValue` (≈ 2 To en KB) pour éviter un débordement lors de l'écriture DWORD — aucune machine grand public réelle n'atteint cette limite, ce plafond est une protection, pas une valeur magique arbitraire.

- [x] **Step 3 : Vérifier**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/tweaks-catalog.json','utf8')); console.log('JSON OK')"` → `JSON OK`
Run: `powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'engine/Engine.ps1'), [ref]$null, [ref]$null); Write-Host 'Syntaxe OK'"` → `Syntaxe OK`

- [x] **Step 4 : Commit**

```
git add data/tweaks-catalog.json engine/Engine.ps1
git commit -m "Ajouter 5 tweaks demarrage (fast startup, timeouts, svchost split, IFEO priority)"
```

**Statut d'execution : DONE.** Implemente par subagent (commit `bc2db34`). Spec-compliant (revue independante : 5 entrees catalogue et 4 fonctions handler conformes caractere pour caractere). Code-quality "approved with follow-ups" a releve 2 points Importants : (1) `Set-HandlerState_ShutdownTimeoutsReduce` n'appelait pas `Backup-RegistryKey` avant ecriture, contrairement a `Set-HandlerState_SvchostSplitDynamic` juste en dessous dans le meme diff ; (2) `Get-HandlerState_SvchostSplitDynamic` recalculait le seuil de comparaison sur la RAM courante plutot que sur la RAM au moment de l'activation, risquant un affichage d'etat incoherent si la RAM physique changeait (VM a memoire dynamique notamment). Corriges immediatement (commit `d7c36cc`) : ajout de `Backup-RegistryKey` pour les deux cles HKLM/HKCU dans `ShutdownTimeoutsReduce`, et `Get-HandlerState_SvchostSplitDynamic` simplifie pour se baser sur la simple presence de la valeur de registre (coherent avec le fait que le seuil pose par ce tweak est toujours superieur a la RAM par construction). Verifie syntaxiquement OK apres correctif.

---

### Task 6 : Catégorie Services — 2 tweaks (`kind: service`, pas de code moteur)

**Files:**
- Modify: `data/tweaks-catalog.json` (ajouter 2 entrées)

- [x] **Step 1 : Ajouter les 2 entrées catalogue**

Insérer avant le `]` final :

```json
  ,
  {
    "id": "service-diagtrack",
    "category": "services",
    "risk": "intermediaire",
    "type": "toggle",
    "kind": "service",
    "serviceName": "DiagTrack",
    "onValue": "Disabled",
    "offValue": "Automatic",
    "defaultValue": "Automatic",
    "requiresRestart": false,
    "label": "Service de télémétrie \"Connected User Experiences and Telemetry\"",
    "description": "Coupe le service central de collecte de télémétrie Windows (DiagTrack). N'a aucun effet sur Windows Update ou Defender."
  },
  {
    "id": "service-dmwappush",
    "category": "services",
    "risk": "basique",
    "type": "toggle",
    "kind": "service",
    "serviceName": "dmwappushservice",
    "onValue": "Disabled",
    "offValue": "Manual",
    "defaultValue": "Manual",
    "requiresRestart": false,
    "label": "Service WAP Push Message Routing",
    "description": "Service hérité du routage de messages WAP Push, quasi jamais utilisé sur un PC de bureau moderne."
  }
```

- [x] **Step 2 : Vérifier**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/tweaks-catalog.json','utf8')); console.log('JSON OK')"` → `JSON OK`

- [x] **Step 3 : Commit**

```
git add data/tweaks-catalog.json
git commit -m "Ajouter les services DiagTrack et dmwappushservice (categorie Services)"
```

**Statut d'execution : DONE.** Tache purement declarative (2 entrees JSON `kind: service`, aucun code moteur requis, dispatcher generique existant suffit). Implemente par subagent (commit `1b3d7b6`). Diff verifie ligne a ligne contre la spec (identique), JSON valide. Vu la simplicite mecanique et le diff deja confirme exact, revue effectuee directement plutot que via subagents spec/qualite dedies — aucun probleme trouve.

---

### Task 7 : Catégorie Confidentialité — 5 tweaks (dont `windows-recall-disable` avec garde NPU)

**Files:**
- Modify: `data/tweaks-catalog.json` (ajouter 5 entrées)
- Modify: `engine/Engine.ps1` (ajouter 2 fonctions dans une nouvelle section "Handlers nommes : Confidentialite (suite)")

- [x] **Step 1 : Ajouter les 5 entrées catalogue**

Insérer avant le `]` final :

```json
  ,
  {
    "id": "start-menu-suggestions-disable",
    "category": "confidentialite",
    "risk": "basique",
    "type": "toggle",
    "kind": "handler",
    "handler": "StartMenuSuggestionsDisable",
    "requiresRestart": false,
    "requiresExplorerRestart": true,
    "label": "Bloquer les suggestions et publicités du menu Démarrer / écran de verrouillage",
    "description": "Coupe les applications suggérées, les astuces et le contenu \"spotlight\" sur le menu Démarrer et l'écran de verrouillage."
  },
  {
    "id": "werror-reporting-disable",
    "category": "confidentialite",
    "risk": "intermediaire",
    "type": "toggle",
    "kind": "registry",
    "path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\Windows Error Reporting",
    "name": "Disabled",
    "regType": "DWord",
    "onValue": 1,
    "offValue": 0,
    "defaultValue": 0,
    "requiresRestart": false,
    "label": "Désactiver le rapport d'erreurs Windows",
    "description": "Empêche Windows d'envoyer des rapports d'erreur (crash dumps applicatifs) à Microsoft."
  },
  {
    "id": "advertising-id-disable",
    "category": "confidentialite",
    "risk": "basique",
    "type": "toggle",
    "kind": "registry",
    "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\AdvertisingInfo",
    "name": "Enabled",
    "regType": "DWord",
    "onValue": 0,
    "offValue": 1,
    "defaultValue": 1,
    "requiresRestart": false,
    "label": "Désactiver l'ID de publicité",
    "description": "Empêche les applications d'utiliser l'identifiant publicitaire Windows pour personnaliser les publicités."
  },
  {
    "id": "windows-recall-disable",
    "category": "confidentialite",
    "risk": "basique",
    "type": "toggle",
    "kind": "registry",
    "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsAI",
    "name": "AllowRecallEnablement",
    "regType": "DWord",
    "onValue": 0,
    "offValue": null,
    "defaultValue": null,
    "guardRequiresDeviceClass": "ComputeAccelerator",
    "requiresRestart": false,
    "label": "Désactiver Windows Recall",
    "description": "Bloque l'activation de Windows Recall via la stratégie de groupe. Ce tweak n'apparaît que si un NPU est détecté sur ta machine (Recall nécessite un Copilot+ PC)."
  },
  {
    "id": "cloud-clipboard-disable",
    "category": "confidentialite",
    "risk": "basique",
    "type": "toggle",
    "kind": "registry",
    "path": "HKCU:\\Software\\Microsoft\\Clipboard",
    "name": "EnableCloudClipboard",
    "regType": "DWord",
    "onValue": 0,
    "offValue": 1,
    "defaultValue": 1,
    "requiresRestart": false,
    "label": "Désactiver la synchronisation cloud du presse-papiers",
    "description": "Coupe la synchronisation du presse-papiers entre appareils Microsoft (\"Sync across your devices\"). N'affecte pas l'historique local du presse-papiers (Win+V)."
  }
```

- [x] **Step 2 : Ajouter la fonction handler `StartMenuSuggestionsDisable`**

Ajouter à la fin de la section `# Handlers nommes : Confidentialite` existante, juste après `Set-HandlerState_ScheduledTasksTelemetry` (avant `# ============================================================` / `# Handlers nommes : Services (MMCSS)`, autour de la ligne 419) :

```powershell
function Get-HandlerState_StartMenuSuggestionsDisable {
    $v = Get-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SystemPaneSuggestionsEnabled'
    if ("$v" -eq '0') { return 'on' }
    return 'off'
}

function Set-HandlerState_StartMenuSuggestionsDisable {
    param([bool]$Enabled)
    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $names = @('SystemPaneSuggestionsEnabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled', 'RotatingLockScreenEnabled', 'RotatingLockScreenOverlayEnabled')
    $value = if ($Enabled) { 0 } else { 1 }
    foreach ($n in $names) { Set-RegValue -Path $path -Name $n -Value $value -Type DWord }
    Write-EngineLog "Suggestions Start Menu/verrouillage -> Enabled(desactivees)=$Enabled" 'OK'
}
```

(`werror-reporting-disable`, `advertising-id-disable`, `windows-recall-disable`, `cloud-clipboard-disable` sont tous `kind: registry` — aucune fonction moteur requise.)

- [x] **Step 3 : Vérifier**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/tweaks-catalog.json','utf8')); console.log('JSON OK')"` → `JSON OK`
Run: `powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'engine/Engine.ps1'), [ref]$null, [ref]$null); Write-Host 'Syntaxe OK'"` → `Syntaxe OK`

- [x] **Step 4 : Commit**

```
git add data/tweaks-catalog.json engine/Engine.ps1
git commit -m "Ajouter 5 tweaks confidentialite dont windows-recall-disable (garde NPU)"
```

**Statut d'execution : DONE.** Implemente par subagent (commit `823732e`). Spec-compliance : ✅ conforme (revue subagent independante, diff verifie caractere pour caractere). Code-quality : "Changes requested" — 1 point Important releve : `Set-HandlerState_StartMenuSuggestionsDisable` ecrasait inconditionnellement 5 valeurs de registre sans capturer l'etat prealable (contrairement au pattern `Save-EngineState`/`Get-EngineState` deja etabli par `WidgetsCopilotBing` dans le meme fichier), risquant de reactiver des suggestions que l'utilisateur avait lui-meme desactivees. Corrige immediatement (commit `ac76d6e`) en appliquant le meme pattern de capture/restauration. Syntaxe verifiee OK apres correctif.

---

### Task 8 : Enregistrer les 4 nouvelles catégories dans l'UI

**Files:**
- Modify: `renderer/app.js:2-11` (`CATEGORY_META`)
- Modify: `renderer/app.js:11` (`CATEGORY_ORDER`)

- [x] **Step 1 : Étendre `CATEGORY_META`**

Remplacer :

```javascript
  const CATEGORY_META = {
    alimentation: { label: 'Alimentation', desc: 'Plans d\'alimentation et gestion de l\'energie du CPU/USB.' },
    reseau: { label: 'Reseau', desc: 'Latence, Nagle, RSS et economie d\'energie de la carte reseau.' },
    affichage: { label: 'Affichage', desc: 'HAGS, MSI Mode et effets visuels pour la fluidite et la visibilite.' },
    jeux: { label: 'Jeux', desc: 'Mode Jeu, GameDVR/overlay et preference GPU par executable.' },
    demarrage: { label: 'Demarrage', desc: 'Applications au demarrage de Windows et desinstallation du bloatware.' },
    services: { label: 'Services', desc: 'Services Windows non essentiels et priorite MMCSS pour le jeu au premier plan.' },
    confidentialite: { label: 'Confidentialite', desc: 'Widgets, Copilot, suggestions Bing et taches planifiees de telemetrie produit (jamais Windows Update / Defender).' }
  };
  const CATEGORY_ORDER = ['alimentation', 'reseau', 'affichage', 'jeux', 'demarrage', 'services', 'confidentialite'];
```

par :

```javascript
  const CATEGORY_META = {
    alimentation: { label: 'Alimentation', desc: 'Plans d\'alimentation et gestion de l\'energie du CPU/USB.' },
    reseau: { label: 'Reseau', desc: 'Latence, Nagle, RSS et economie d\'energie de la carte reseau.' },
    affichage: { label: 'Affichage', desc: 'HAGS, MSI Mode et effets visuels pour la fluidite et la visibilite.' },
    jeux: { label: 'Jeux', desc: 'Mode Jeu, GameDVR/overlay et preference GPU par executable.' },
    demarrage: { label: 'Demarrage', desc: 'Applications au demarrage de Windows et desinstallation du bloatware.' },
    services: { label: 'Services', desc: 'Services Windows non essentiels et priorite MMCSS pour le jeu au premier plan.' },
    confidentialite: { label: 'Confidentialite', desc: 'Widgets, Copilot, suggestions Bing et taches planifiees de telemetrie produit (jamais Windows Update / Defender).' },
    audio: { label: 'Audio', desc: 'Latence audio et priorite MMCSS pour la capture/lecture son.' },
    peripheriques: { label: 'Peripheriques', desc: 'Souris, clavier et USB : latence d\'entree et acceleration.' },
    latence: { label: 'Latence', desc: 'Timers systeme, IRQ et synchronisation horloge pour la reactivite CPU.' },
    productivite: { label: 'Productivite', desc: 'Alt+Tab, Snap Assist et barre des taches multi-ecrans.' }
  };
  const CATEGORY_ORDER = ['alimentation', 'reseau', 'affichage', 'jeux', 'demarrage', 'services', 'confidentialite', 'audio', 'peripheriques', 'latence', 'productivite'];
```

- [x] **Step 2 : Vérifier**

Run: `node --check renderer/app.js` → aucune sortie

- [x] **Step 3 : Vérification manuelle immédiate**

Run: `npm start` (depuis `D:\workspace\WinOptiApp`), vérifier que les 4 nouvelles catégories apparaissent dans la sidebar avec un badge "0/0" (aucun tweak encore ajouté) et qu'elles s'ouvrent sans erreur (page vide, pas de crash). Fermer l'app ensuite.

- [x] **Step 4 : Commit**

```
git add renderer/app.js
git commit -m "Enregistrer les 4 nouvelles categories (audio, peripheriques, latence, productivite)"
```

**Statut d'execution : DONE (avec limitation notee).** Implemente par subagent (commit `26b9a6e`), diff verifie caractere pour caractere contre la spec. `node --check` OK. La verification GUI reelle via `npm start` n'a pas pu etre executee dans cet environnement : l'outil de previsualisation navigateur disponible ne sait piloter que des serveurs web (URL/port), pas une fenetre native Electron. A la place, inspection statique du code de rendu (`categoryCounts` ligne 55, `renderCategoryPage` ligne 222) : les deux fonctions iterent sur des tableaux (`forEach`/`some`/`.length`) sans hypothese de non-vacuite, donc une categorie a 0 entree ne provoque ni exception ni division par zero — badge "0/0" et page vide attendus sans crash. Verification visuelle reelle recommandee par l'utilisateur lors d'un prochain lancement manuel de l'app.

---

### Task 9 : Catégorie Audio (nouvelle) — `mmcss-audio-priority` + liste spéciale `audio-device-list`

**Files:**
- Modify: `data/tweaks-catalog.json` (ajouter 2 entrées)
- Modify: `engine/Engine.ps1` (nouvelle section handler + 2 nouvelles actions `Invoke-*AudioDevice*` + dispatch)
- Modify: `renderer/app.js` (dispatch `renderSpecialWidget` + fonction `renderAudioDeviceList`)

- [x] **Step 1 : Ajouter les 2 entrées catalogue**

Insérer avant le `]` final :

```json
  ,
  {
    "id": "mmcss-audio-priority",
    "category": "audio",
    "risk": "intermediaire",
    "type": "toggle",
    "kind": "handler",
    "handler": "MmcssAudioPriority",
    "requiresRestart": false,
    "label": "Priorité MMCSS renforcée pour l'audio",
    "description": "Augmente la priorité CPU/GPU accordée aux tâches multimédias \"Audio\" et \"Pro Audio\" par le planificateur MMCSS. Réduit les craquements/glitches audio sous charge CPU importante."
  },
  {
    "id": "audio-enhancements-disable",
    "category": "audio",
    "risk": "intermediaire",
    "type": "audio-device-list",
    "requiresRestart": false,
    "label": "Désactiver les améliorations audio par périphérique",
    "description": "Coupe la virtualisation/égalisation logicielle de Windows (par périphérique de sortie), qui ajoute de la latence. Laisse le logiciel du périphérique (casque, DAC) gérer les effets si besoin."
  }
```

- [x] **Step 2 : Ajouter la section handler + les actions de liste dans `engine/Engine.ps1`**

Ajouter une nouvelle section juste avant `# ============================================================` / `# Listes dynamiques : demarrage, debloat, preference GPU` (après la section "Handlers nommes : Demarrage" ajoutée en Task 5) :

```powershell
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
```

- [x] **Step 3 : Câbler les 2 nouvelles actions dans le dispatch principal**

Dans le bloc `switch ($Action)`, ajouter après les 3 lignes `*FullscreenOptApp*` ajoutées en Task 4 :

```powershell
        'ListAudioDevices' { Invoke-ListAudioDevices }
        'SetAudioDeviceEffects' { Invoke-SetAudioDeviceEffects -Payload $Script:Payload; $null }
```

- [x] **Step 4 : Ajouter le rendu UI dans `renderer/app.js`**

Remplacer la ligne (mise à jour en Task 4) :

```javascript
    if (entry.type === 'fullscreen-opt-list') return renderFullscreenOptList(entry);
```

par :

```javascript
    if (entry.type === 'fullscreen-opt-list') return renderFullscreenOptList(entry);
    if (entry.type === 'audio-device-list') return renderAudioDeviceList(entry);
```

Puis ajouter la fonction `renderAudioDeviceList` juste après `renderFullscreenOptList` :

```javascript
  async function renderAudioDeviceList(entry) {
    sectionTitle(entry.label);
    const listHolder = document.createElement('div');
    contentEl.appendChild(listHolder);

    async function load() {
      listHolder.innerHTML = '<div class="spinner-note">Chargement...</div>';
      const res = await window.api.callEngine('ListAudioDevices');
      listHolder.innerHTML = '';
      if (!res.ok) { listHolder.innerHTML = `<div class="empty-state">${res.error}</div>`; return; }
      if (!res.data || !res.data.length) { listHolder.innerHTML = '<div class="empty-state">Aucun peripherique de sortie audio detecte.</div>'; return; }
      res.data.forEach((device) => {
        const row = document.createElement('div');
        row.className = 'list-row';
        const main = document.createElement('div');
        main.className = 'list-row-main';
        const title = document.createElement('div');
        title.className = 'list-row-title';
        title.textContent = device.name;
        main.appendChild(title);
        row.appendChild(main);
        const sw = document.createElement('div');
        sw.className = 'switch' + (device.enhancementsDisabled ? ' on' : '');
        const knob = document.createElement('div');
        knob.className = 'switch-knob';
        sw.appendChild(knob);
        sw.addEventListener('click', async () => {
          const newDisabled = !(sw.classList.contains('on'));
          const r = await window.api.callEngine('SetAudioDeviceEffects', { deviceId: device.id, disabled: newDisabled });
          if (!r.ok) { toast('Echec: ' + r.error, false); return; }
          sw.classList.toggle('on', newDisabled);
        });
        row.appendChild(sw);
        listHolder.appendChild(row);
      });
    }
    await load();
  }
```

- [x] **Step 5 : Vérifier**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/tweaks-catalog.json','utf8')); console.log('JSON OK')"` → `JSON OK`
Run: `powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'engine/Engine.ps1'), [ref]$null, [ref]$null); Write-Host 'Syntaxe OK'"` → `Syntaxe OK`
Run: `node --check renderer/app.js` → aucune sortie

- [x] **Step 6 : Commit**

```
git add data/tweaks-catalog.json engine/Engine.ps1 renderer/app.js
git commit -m "Ajouter la categorie Audio (mmcss-audio-priority + audio-device-list)"
```

**Statut d'execution : DONE.** Implemente par subagent (commit `21e952e`). Spec-compliance : ✅ conforme (revue independante, diff verifie point par point incl. ancrages exacts). Code-quality : **Approved** — 2 points Mineurs releves sans action requise : (1) `Set-HandlerState_MmcssAudioPriority` n'a pas de `Backup-RegistryKey`, mais reproduit exactement le pattern deja present du handler soeur preexistant `MMCSSGamesPriority` (incoherence heritee, pas une regression de cette tache) ; (2) virgule isolee sur sa propre ligne dans le JSON (style deja utilise partout ailleurs dans ce fichier pour les insertions, cosmetique). Verifications syntaxiques toutes OK.

---

### Task 10 : Catégorie Périphériques (nouvelle) — 6 tweaks

**Files:**
- Modify: `data/tweaks-catalog.json` (ajouter 6 entrées)
- Modify: `engine/Engine.ps1` (nouvelle section handler, 4 paires de fonctions ; `mouse-data-queue-size`/`keyboard-data-queue-size` sont `kind: registry`, aucune fonction requise)

- [x] **Step 1 : Ajouter les 6 entrées catalogue**

Insérer avant le `]` final :

```json
  ,
  {
    "id": "mouse-acceleration-disable",
    "category": "peripheriques",
    "risk": "basique",
    "type": "toggle",
    "kind": "handler",
    "handler": "MouseAccelerationDisable",
    "requiresRestart": false,
    "label": "Désactiver l'accélération de la souris",
    "description": "Force un mouvement de souris 1:1 (MouseSpeed/MouseThreshold à 0), sans courbe d'accélération dépendante de la vitesse de déplacement. Recommandé en jeu compétitif."
  },
  {
    "id": "mouse-data-queue-size",
    "category": "peripheriques",
    "risk": "avance",
    "type": "toggle",
    "kind": "registry",
    "path": "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\mouclass\\Parameters",
    "name": "MouseDataQueueSize",
    "regType": "DWord",
    "onValue": 20,
    "offValue": 100,
    "defaultValue": 100,
    "requiresRestart": true,
    "label": "Réduire le buffer d'entrée souris",
    "description": "Réduit la taille de la file d'attente des évènements souris (100 vers 20). Effet non garanti selon les configurations (perçu comme un placebo par certains, réel par d'autres) — teste et compare avant/après."
  },
  {
    "id": "keyboard-data-queue-size",
    "category": "peripheriques",
    "risk": "avance",
    "type": "toggle",
    "kind": "registry",
    "path": "HKLM:\\SYSTEM\\CurrentControlSet\\Services\\kbdclass\\Parameters",
    "name": "KeyboardDataQueueSize",
    "regType": "DWord",
    "onValue": 20,
    "offValue": 100,
    "defaultValue": 100,
    "requiresRestart": true,
    "label": "Réduire le buffer d'entrée clavier",
    "description": "Réduit la taille de la file d'attente des évènements clavier (100 vers 20). Effet non garanti selon les configurations — teste et compare avant/après."
  },
  {
    "id": "keyboard-repeat-accelerate",
    "category": "peripheriques",
    "risk": "basique",
    "type": "toggle",
    "kind": "registry",
    "path": "HKCU:\\Control Panel\\Keyboard",
    "name": "KeyboardDelay",
    "regType": "String",
    "onValue": "0",
    "offValue": "1",
    "defaultValue": "1",
    "requiresRestart": false,
    "label": "Répétition clavier accélérée",
    "description": "Réduit au minimum (0) le délai avant qu'une touche maintenue commence à se répéter."
  },
  {
    "id": "usb-thread-priority",
    "category": "peripheriques",
    "risk": "avance",
    "type": "toggle",
    "kind": "handler",
    "handler": "UsbThreadPriority",
    "requiresRestart": true,
    "label": "Priorité des threads USB",
    "description": "Augmente la priorité des threads de traitement des contrôleurs USB 3 (XHCI). Effet non garanti selon les configurations — mécanisme peu documenté, teste et compare avant/après."
  },
  {
    "id": "csrss-priority",
    "category": "peripheriques",
    "risk": "avance",
    "type": "toggle",
    "kind": "handler",
    "handler": "CsrssPriority",
    "requiresRestart": false,
    "label": "Priorité haute de csrss.exe",
    "description": "Tente d'élever la priorité du processus système csrss.exe. Mécanisme hérité d'avant les protections modernes (Protected Process Light) : sur Windows 11, Windows refuse généralement ce changement et l'application le signale honnêtement au lieu d'afficher un faux succès."
  }
```

- [x] **Step 2 : Ajouter la section handler dans `engine/Engine.ps1`**

Ajouter une nouvelle section juste avant `# ============================================================` / `# Listes dynamiques : demarrage, debloat, preference GPU` (après la section Audio ajoutée en Task 9) :

```powershell
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
    $value = if ($Enabled) { 31 } else { 8 }
    foreach ($p in $paths) {
        Set-RegValue -Path $p -Name 'ThreadPriority' -Value $value -Type DWord
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
```

Remarque sur `CsrssPriority` : conformément au spec, le handler vérifie après coup (`Get-HandlerState_CsrssPriority`) que le changement a réellement pris effet et lève une exception explicite sinon — `Invoke-Apply` capture déjà cette exception et remonte `ok:false` + le message d'erreur au toast UI, aucun changement n'est nécessaire côté dispatch/UI pour ce comportement.

- [x] **Step 3 : Vérifier**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/tweaks-catalog.json','utf8')); console.log('JSON OK')"` → `JSON OK`
Run: `powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'engine/Engine.ps1'), [ref]$null, [ref]$null); Write-Host 'Syntaxe OK'"` → `Syntaxe OK`

- [x] **Step 4 : Commit**

```
git add data/tweaks-catalog.json engine/Engine.ps1
git commit -m "Ajouter la categorie Peripheriques (6 tweaks : souris, clavier, USB, csrss)"
```

**Statut d'execution : DONE.** Implemente par subagent (commit `409a841`). Spec-compliance : ✅ conforme (revue independante, diff verifie champ par champ, ancrages d'insertion exacts, aucune fonction moteur superflue pour les 3 tweaks `kind: registry`). Code-quality : **Changes requested** puis corrige — un point Important releve : `Set-HandlerState_UsbThreadPriority` codait en dur la valeur "off" (`8`) au lieu de `Remove-RegValue`, contrairement au pattern etabli par `NetworkNagle`/`SvchostSplitDynamic` pour restaurer le comportement par defaut de Windows ; corrige immediatement (commit `5094d2a`, fix direct). Points Mineurs restants (aucune action requise, patterns herites) : absence de `Backup-RegistryKey` sur `MouseAccelerationDisable`/`UsbThreadPriority` (incoherence deja presente sur ~50% des handlers similaires du fichier, pas specifique a cette tache) ; `Get-HandlerState_*` de ces deux handlers ne verifient qu'un seul indicateur representatif plutot que toutes les clefs ecrites (meme pattern que `MmcssAudioPriority`). Le comportement `throw`-si-refuse de `CsrssPriority` s'integre correctement avec `Invoke-Apply` (deja verifie par le reviewer). Verifications syntaxiques toutes OK.

---

### Task 11 : Catégorie Latence (nouvelle) — 6 tweaks

**Files:**
- Modify: `data/tweaks-catalog.json` (ajouter 6 entrées)
- Modify: `engine/Engine.ps1` (nouvelle section handler, 4 paires de fonctions ; `global-timer-resolution`/`mmcss-no-lazy-mode` sont `kind: registry`, aucune fonction requise)

- [ ] **Step 1 : Ajouter les 6 entrées catalogue**

Insérer avant le `]` final :

```json
  ,
  {
    "id": "global-timer-resolution",
    "category": "latence",
    "risk": "avance",
    "type": "toggle",
    "kind": "registry",
    "path": "HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\kernel",
    "name": "GlobalTimerResolutionRequests",
    "regType": "DWord",
    "onValue": 1,
    "offValue": 0,
    "defaultValue": 0,
    "requiresRestart": true,
    "label": "Restaurer la résolution timer fine (1ms) pour les jeux",
    "description": "Autorise à nouveau les applications à demander une résolution de timer système fine (1ms), un comportement que Microsoft a restreint pour économiser l'énergie. Un processus mal codé en arrière-plan peut augmenter la consommation de 10 à 25%."
  },
  {
    "id": "dynamic-tick-disable",
    "category": "latence",
    "risk": "avance",
    "type": "toggle",
    "kind": "handler",
    "handler": "DynamicTickDisable",
    "requiresRestart": true,
    "label": "Désactiver le Dynamic Tick",
    "description": "Force le minuteur système à tourner en continu au lieu de réduire sa fréquence en veille pour économiser l'énergie (bcdedit /set disabledynamictick yes). Augmente légèrement la consommation/chaleur au repos. Effectif seulement après redémarrage."
  },
  {
    "id": "tsc-sync-policy-enhanced",
    "category": "latence",
    "risk": "avance",
    "type": "toggle",
    "kind": "handler",
    "handler": "TscSyncPolicyEnhanced",
    "requiresRestart": true,
    "label": "Politique de synchronisation TSC renforcée",
    "description": "Force Windows à synchroniser plus strictement le compteur TSC entre cœurs (bcdedit /set tscsyncpolicy Enhanced). Tweak de niche, surtout utile sur CPU multi-cœurs avec TSC instable. Effectif seulement après redémarrage."
  },
  {
    "id": "hpet-disable",
    "category": "latence",
    "risk": "avance",
    "type": "toggle",
    "kind": "handler",
    "handler": "HpetDisable",
    "requiresRestart": true,
    "label": "Désactiver le HPET (High Precision Event Timer)",
    "description": "Retire le forçage de l'horloge plateforme (bcdedit useplatformclock), laissant Windows choisir automatiquement sa source d'horloge (généralement le TSC sur CPU moderne). Effet non consensuel selon les configurations — teste et compare. Effectif seulement après redémarrage."
  },
  {
    "id": "mmcss-no-lazy-mode",
    "category": "latence",
    "risk": "avance",
    "type": "toggle",
    "kind": "registry",
    "path": "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile",
    "name": "NoLazyMode",
    "regType": "DWord",
    "onValue": 1,
    "offValue": 0,
    "defaultValue": 0,
    "requiresRestart": true,
    "label": "Désactiver le \"Lazy Mode\" MMCSS",
    "description": "Empêche le planificateur multimédia MMCSS de retarder paresseusement le traitement de certaines tâches. Non documenté officiellement par Microsoft, effet empirique selon la communauté."
  },
  {
    "id": "irq-priority-tuning",
    "category": "latence",
    "risk": "avance",
    "type": "toggle",
    "kind": "handler",
    "handler": "IrqPriorityTuning",
    "requiresRestart": true,
    "label": "Priorité IRQ horloge/GPU",
    "description": "Priorise l'IRQ8 (horloge système) et l'IRQ du GPU détecté dynamiquement sur ta machine. Mécanisme hérité, effet non garanti — inopérant si le GPU utilise le MSI Mode (pas d'IRQ classique à prioriser)."
  }
```

- [ ] **Step 2 : Ajouter la section handler dans `engine/Engine.ps1`**

Ajouter une nouvelle section juste avant `# ============================================================` / `# Listes dynamiques : demarrage, debloat, preference GPU` (après la section Périphériques ajoutée en Task 10) :

```powershell
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
    if ($Enabled) {
        & bcdedit /deletevalue '{current}' useplatformclock 2>&1 | Out-Null
    } else {
        & bcdedit /set '{current}' useplatformclock true | Out-Null
    }
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
```

Remarques de conception :
- `dynamic-tick-disable`/`tsc-sync-policy-enhanced`/`hpet-disable` suivent tous le motif "état sauvegardé via `Save-EngineState`" (identique à `power-plan-ultimate`) plutôt que de parser la sortie texte de `bcdedit /enum`, qui est localisée selon la langue d'affichage Windows et donc fragile à analyser de façon fiable.
- `irq-priority-tuning` découvre dynamiquement l'IRQ du GPU via WMI (`Win32_PNPAllocatedResource`) au lieu d'un numéro d'IRQ figé en dur — si le GPU utilise déjà le MSI Mode, il n'a plus d'IRQ classique et la fonction le journalise en `WARN` sans échouer (l'IRQ8 horloge est tout de même appliquée).

- [ ] **Step 3 : Vérifier**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/tweaks-catalog.json','utf8')); console.log('JSON OK')"` → `JSON OK`
Run: `powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'engine/Engine.ps1'), [ref]$null, [ref]$null); Write-Host 'Syntaxe OK'"` → `Syntaxe OK`

- [ ] **Step 4 : Commit**

```
git add data/tweaks-catalog.json engine/Engine.ps1
git commit -m "Ajouter la categorie Latence (timer, dynamic tick, TSC, HPET, MMCSS, IRQ)"
```

---

### Task 12 : Catégorie Productivité (nouvelle) — 3 tweaks

**Files:**
- Modify: `data/tweaks-catalog.json` (ajouter 3 entrées)
- Modify: `engine/Engine.ps1` (nouvelle section handler, 1 paire de fonctions ; `alttab-filter-apps-only`/`snap-assist-flyout-enable` sont `kind: registry`, aucune fonction requise)

- [ ] **Step 1 : Ajouter les 3 entrées catalogue**

Insérer avant le `]` final :

```json
  ,
  {
    "id": "alttab-filter-apps-only",
    "category": "productivite",
    "risk": "basique",
    "type": "toggle",
    "kind": "registry",
    "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
    "name": "MultiTaskingAltTabFilter",
    "regType": "DWord",
    "onValue": 3,
    "offValue": 0,
    "defaultValue": 0,
    "requiresRestart": false,
    "requiresExplorerRestart": true,
    "label": "Filtrer Alt+Tab sur les fenêtres d'application seules",
    "description": "Alt+Tab n'affiche plus que les fenêtres d'application (0 = fenêtres + tous les onglets Edge par défaut). Le nom du réglage est trompeur : il ne filtre que les onglets Microsoft Edge, pas ceux des autres navigateurs. Nécessite une déconnexion/reconnexion ou un redémarrage de l'Explorateur pour prendre pleinement effet."
  },
  {
    "id": "snap-assist-flyout-enable",
    "category": "productivite",
    "risk": "basique",
    "type": "toggle",
    "kind": "registry",
    "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced",
    "name": "EnableSnapAssistFlyout",
    "regType": "DWord",
    "onValue": 1,
    "offValue": 0,
    "defaultValue": 1,
    "requiresRestart": false,
    "label": "Activer le flyout Snap Assist",
    "description": "Affiche la miniature de survol proposant de remplir l'autre moitié de l'écran quand tu accroches une fenêtre (Win+flèche)."
  },
  {
    "id": "taskbar-multi-monitor-show-all",
    "category": "productivite",
    "risk": "basique",
    "type": "toggle",
    "kind": "handler",
    "handler": "TaskbarMultiMonitorShowAll",
    "requiresRestart": false,
    "requiresExplorerRestart": true,
    "label": "Afficher la barre des tâches sur tous les écrans",
    "description": "Active la barre des tâches sur chaque moniteur, avec les fenêtres ouvertes regroupées par écran plutôt que dupliquées partout."
  }
```

- [ ] **Step 2 : Ajouter la section handler dans `engine/Engine.ps1`**

Ajouter une nouvelle section juste avant `# ============================================================` / `# Listes dynamiques : demarrage, debloat, preference GPU` (après la section Latence ajoutée en Task 11) :

```powershell
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
```

- [ ] **Step 3 : Vérifier**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/tweaks-catalog.json','utf8')); console.log('JSON OK')"` → `JSON OK`
Run: `powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'engine/Engine.ps1'), [ref]$null, [ref]$null); Write-Host 'Syntaxe OK'"` → `Syntaxe OK`

- [ ] **Step 4 : Commit**

```
git add data/tweaks-catalog.json engine/Engine.ps1
git commit -m "Ajouter la categorie Productivite (Alt+Tab, Snap Assist, barre des taches multi-ecrans)"
```

---

### Task 13 : Vérification finale bout-en-bout

**Files:** aucun (vérification uniquement)

- [ ] **Step 1 : Vérifier le compte total d'entrées du catalogue**

Run: `node -e "const c = JSON.parse(require('fs').readFileSync('data/tweaks-catalog.json','utf8')); console.log('Total entrees:', c.length); console.log('Categories:', [...new Set(c.map(e => e.category))].sort());"`
Expected: `Total entrees: 61` (22 initiales + 39 nouvelles), `Categories:` doit lister les 11 catégories : `[ 'affichage', 'alimentation', 'audio', 'confidentialite', 'demarrage', 'jeux', 'latence', 'peripheriques', 'productivite', 'reseau', 'services' ]`.

- [ ] **Step 2 : Vérifier qu'aucun `id` n'est dupliqué**

Run: `node -e "const c = JSON.parse(require('fs').readFileSync('data/tweaks-catalog.json','utf8')); const ids = c.map(e => e.id); const dupes = ids.filter((id, i) => ids.indexOf(id) !== i); console.log(dupes.length ? 'DOUBLONS: ' + dupes.join(',') : 'Aucun doublon');"`
Expected: `Aucun doublon`

- [ ] **Step 3 : Syntaxe complète moteur + renderer**

Run: `powershell -NoProfile -Command "$null = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'engine/Engine.ps1'), [ref]$null, [ref]$null); Write-Host 'Syntaxe OK'"` → `Syntaxe OK`
Run: `node --check renderer/app.js` → aucune sortie

- [ ] **Step 4 : Vérification manuelle bout-en-bout via `npm start`**

Depuis `D:\workspace\WinOptiApp`, lancer `npm start` **en administrateur** (plusieurs handlers touchent HKLM et des services). Pour chacune des 11 catégories dans la sidebar :
1. Ouvrir la catégorie, vérifier que tous les tweaks attendus s'affichent avec label/description/badge de risque corrects, sans erreur JS dans la console Electron (DevTools).
2. Pour `audio` : vérifier que la liste de périphériques audio se charge (section "Désactiver les améliorations audio par périphérique") et qu'un interrupteur bascule sans erreur.
3. Pour `jeux` : vérifier que "Ajouter un exécutable..." fonctionne pour la liste `fullscreen-opt-list` (nouvelle liste) tout comme pour la liste GPU existante.
4. Pour `confidentialite` : vérifier que `windows-recall-disable` n'apparaît QUE si un NPU est détecté sur la machine de test (sinon la carte doit être absente, pas juste grisée) — si la machine de test n'a pas de NPU, confirmer son absence complète de la page.
5. Activer puis désactiver 2-3 tweaks au hasard par catégorie (privilégier les `risk: "basique"`), cliquer "Appliquer", vérifier le toast de succès, puis "Réinitialiser cette catégorie" et confirmer le retour à l'état par défaut.
6. Vérifier spécifiquement `csrss-priority` : l'application doit afficher un toast d'ÉCHEC avec le message expliquant la protection PPL (comportement attendu, pas un bug).
7. Fermer l'app.

- [ ] **Step 5 : Commit final (si des ajustements ont été faits pendant la vérification manuelle)**

```
git add -A
git commit -m "Verification finale Chantier 1 : 61 entrees catalogue, 11 categories"
```

(Ne committer que si des changements ont réellement été nécessaires pendant cette étape — sinon, passer directement à la clôture du plan.)
