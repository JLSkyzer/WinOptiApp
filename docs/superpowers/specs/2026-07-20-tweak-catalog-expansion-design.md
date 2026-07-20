# Extension du catalogue de tweaks (gaming + bureautique) — conception

Date : 2026-07-20
Statut : approuvé par l'utilisateur, en attente de plan d'implémentation
Chantier : 1 sur 2 (voir Hors scope pour le chantier 2)

## Contexte

Suite à la refonte de la page Guide manuel ([[2026-07-20-guide-manuel-redesign-design]]),
l'utilisateur a demandé une recherche large pour étoffer le catalogue de tweaks
automatisés (`data/tweaks-catalog.json`, 22 entrées / 7 catégories actuellement), avec
deux axes : le gaming (cœur historique de l'app) et le "bureautique" (démarrage/
réactivité générale, confidentialité/télémétrie renforcée, productivité multi-écran/
multitâche — explicitement hors scope : le nettoyage disque).

Une recherche a été menée (web + inspection du pack `D:\Pack d'Opti RayOptimizer`,
ancien pack d'optimisation dont l'utilisateur n'a pas aimé l'approche globale mais qui
contient des tweaks individuels réutilisables) et a produit ~43 candidats. Ce document
couvre la sélection retenue et la façon de l'intégrer au catalogue.

## Décisions validées

1. **Uniquement du natif PowerShell/registre/service/cmdlet** est automatisé dans le
   catalogue. Tout ce qui nécessite un outil tiers empaqueté (Process Lasso, ParkControl,
   NVCleanstall, etc.) part en entrée de guide manuel avec un lien — traité dans le
   Chantier 2, hors scope de ce document.
2. **Nouvelles catégories dédiées** créées plutôt que de tout entasser dans les 7
   catégories existantes : `audio`, `peripheriques`, `latence`, `productivite`.
3. **Aucun tweak à compromis sécuritaire** : VBS, désactivation des mitigations
   Spectre/Meltdown, désactivation de Windows Defender temps réel — explicitement exclus,
   ne figurent nulle part (ni catalogue, ni guide manuel).
4. **Les tweaks à fiabilité incertaine sont inclus, pas exclus** : ceux dont l'effet réel
   est peu recoupé par une source fiable (ex. Mouse/Keyboard Data Queue Size, MMCSS
   NoLazyMode, priorité IRQ) gardent `risk: "avance"` et leur `description` porte une
   mention honnête du type *"Effet non garanti selon les configurations — teste et
   compare avant/après"*, dans le même esprit que le tweak `service-sysmain` existant
   ("Teste et compare sur ta machine"). Pas de nouveau champ de schéma pour ça : c'est
   une convention rédactionnelle sur `description`, cohérente avec l'existant.
5. **Contradiction écartée** : RayOptimizer inclut un throttle des connexions Windows
   Update — ceci contredit le principe déjà en vigueur dans ce catalogue ("ne jamais
   toucher aux tâches Windows Update", cf. `scheduled-tasks-telemetry` qui s'arrête
   volontairement aux tâches de télémétrie). Ce tweak n'est pas repris ; seule sa
   variante douce (priorité réduite de `TiWorker.exe`, qui ne bloque rien) est retenue.
6. **Mécanismes non confirmés avec certitude ne sont pas automatisés** : deux items
   (filtrage de la barre des tâches par bureau virtuel, mémorisation d'emplacement des
   fenêtres par écran) reposent sur des clés de registre non vérifiées de façon fiable
   pendant la recherche — plutôt que d'automatiser un mécanisme incertain, ils sont
   renvoyés en candidats de guide manuel (Chantier 2, avec lien vers les paramètres
   Windows natifs `ms-settings:`).

## Modification de schéma : nouveau `kind: "device-list"`

Deux tweaks audio (désactivation des améliorations audio, mode exclusif) s'appliquent à
un périphérique de sortie audio choisi par l'utilisateur, pas à une clé de registre
globale unique. Le moteur actuel connaît déjà les motifs `registry` (générique) et
`handler` (fonctions dédiées) ; on ajoute un troisième motif :

```json
{
  "id": "audio-enhancements-disable",
  "category": "audio",
  "risk": "intermediaire",
  "type": "toggle",
  "kind": "device-list",
  "deviceClass": "audio-render",
  "propertyKey": "{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},0",
  "regType": "DWord",
  "onValue": 1,
  "offValue": 0,
  "defaultValue": 0,
  "requiresRestart": false,
  "label": "Désactiver les améliorations audio",
  "description": "Coupe la virtualisation/égalisation logicielle de Windows (par périphérique), qui ajoute de la latence. Laisse le logiciel du périphérique (casque, DAC) gérer les effets si besoin."
}
```

Fonctionnement moteur :
- `Invoke-GetAudioDevices` (nouvelle fonction) énumère les sous-clés de
  `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\*`, lit le nom
  convivial de chaque périphérique (via son magasin de propriétés), et retourne une
  liste `{id: <GUID>, name: <nom lisible>}`.
- `Get-DeviceListToggleState` / `Set-DeviceListToggleValue` (génériques, sur le modèle de
  `Get-ToggleState`/`Set-ToggleValue` existants) prennent en plus un `deviceId` et lisent/
  écrivent la propriété `propertyKey` sous
  `...\Render\<deviceId>\FxProperties` (ou `\Properties` selon la propriété visée).
- Le mécanisme exact de la propriété "mode exclusif" (deuxième tweak `device-list`,
  `audio-exclusive-mode`) n'a pas été confirmé avec un niveau de confiance suffisant
  pendant la recherche — **à valider techniquement lors de l'écriture du plan**
  (test sur une machine réelle avant de figer la clé), plutôt que d'inventer une valeur.
  La propriété `PKEY_AudioEndpoint_Disable_SysFx` ci-dessus (améliorations audio) est en
  revanche un mécanisme bien documenté et peut être figée telle quelle.

Impact UI (`renderer/`) : la page catégorie "Audio" doit proposer un sélecteur de
périphérique (liste déroulante alimentée par `Invoke-GetAudioDevices`) au-dessus des deux
tweaks `device-list`, qui n'affichent leur état/toggle qu'une fois un périphérique
sélectionné. C'est le seul ajout d'UI non trivial de ce chantier (le reste ce sont des
toggles simples s'intégrant dans les pages de catégorie existantes).

## Tweaks à automatiser, par catégorie

Format : `id` — label — mécanisme — risque.

**Alimentation** (existante)
- `cpu-boost-aggressive` — Mode Boost Processeur agressif — `powercfg -attributes` +
  `HKLM\...\Power\PowerSettings\...\be337238-0d82-4146-a960-4f3749d470c7` — avancé (conso/
  chaleur, surtout portable)

**Réseau** (existante)
- `network-throttling-unlimited` — Suppression de la limitation réseau multimédia —
  `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\NetworkThrottlingIndex`
  = 0xffffffff — intermédiaire
- `network-ipv6-disable` — Désactiver IPv6 — `Disable-NetAdapterBinding -ComponentID ms_tcpip6`
  — intermédiaire (peut casser des services IPv6-only)
- `delivery-optimization-http-only` — Delivery Optimization en HTTP seul (pas de P2P) —
  `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization\DODownloadMode` = 0 —
  basique
- `network-power-management-disable` — Désactiver la gestion d'énergie de la carte
  réseau — `Disable-NetAdapterPowerManagement` — basique
- `msi-mode-network` — Extension du MSI Mode existant (GPU+USB) aux contrôleurs réseau —
  même mécanique registre par classe de périphérique — intermédiaire
- `dns-fast` — Basculer vers un résolveur DNS rapide (Cloudflare 1.1.1.1) —
  `Set-DnsClientServerAddress` — basique

**Affichage / Jeux** (existantes)
- `fullscreen-optimizations-disable` — Désactiver les optimisations plein écran par jeu
  (motif liste d'exécutables, comme `gpu-preference-game`) —
  `HKCU\...\AppCompatFlags\Layers` (`DISABLEDXMAXIMIZEDWINDOWEDMODE`) — intermédiaire (ne
  s'applique qu'aux jeux DX9-11)
- `tdr-delay-increase` — Augmenter le délai TDR — `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\TdrDelay`
  — avancé — *description doit mentionner que Microsoft déconseille cette clé aux
  utilisateurs finaux et qu'un vrai problème driver mettra plus longtemps à récupérer*
- `gpu-preemption-disable` — Désactiver la préemption GPU — clé `GraphicsDrivers`, source
  RayOptimizer uniquement — avancé — *description porte la mention "effet non garanti"*

**Démarrage** (existante)
- `fast-startup-disable` — Désactiver le Démarrage rapide —
  `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power\HiberbootEnabled` = 0 —
  basique
- `shutdown-timeouts-reduce` — Réduire les délais d'arrêt —
  `HKLM`/`HKCU\Control Panel\Desktop` (`WaitToKillServiceTimeout`, `HungAppTimeout`,
  `AutoEndTasks`) — basique
- `svchost-split-dynamic` — Fusion intelligente des svchost selon la RAM détectée
  (handler qui lit `Get-CimInstance Win32_ComputerSystem` et calcule
  `SvcHostSplitThresholdInKB`) — avancé
- `searchindexer-priority-reduce` — Priorité CPU réduite pour SearchIndexer.exe (sans
  désactiver l'indexation) — IFEO
  `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\SearchIndexer.exe\PerfOptions\CpuPriorityClass`
  — avancé
- `tiworker-priority-reduce` — Priorité CPU réduite pour TiWorker.exe (le worker Windows
  Update, sans bloquer les mises à jour elles-mêmes) — même mécanisme IFEO — avancé

**Services** (existante)
- `service-diagtrack` — Service de télémétrie "Connected User Experiences and
  Telemetry" (`DiagTrack`) — motif `kind: service` identique à `service-fax` —
  intermédiaire
- `service-dmwappush` — Service WAP Push Message Routing (`dmwappushservice`) — même
  motif — basique

**Confidentialité** (existante)
- `start-menu-suggestions-disable` — Bloquer suggestions/pub Start Menu et écran de
  verrouillage — `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager`
  — basique
- `werror-reporting-disable` — Désactiver le rapport d'erreurs Windows —
  `HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\Disabled` = 1 — intermédiaire
- `advertising-id-disable` — Désactiver l'ID de publicité —
  `HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo\Enabled` = 0 — basique
- `windows-recall-disable` — Désactiver Windows Recall —
  `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI\AllowRecallEnablement` = 0 —
  basique — *handler doit détecter la présence d'un PC Copilot+ (NPU) et masquer/désactiver
  le tweak si non applicable, plutôt que l'afficher partout*
- `cloud-clipboard-disable` — Désactiver la synchronisation cloud du presse-papiers —
  `HKCU\Software\Microsoft\Clipboard` — basique

**Audio** (nouvelle catégorie)
- `mmcss-audio-priority` — Priorité MMCSS renforcée pour les tâches "Audio"/"Pro Audio" —
  `HKLM\...\Multimedia\SystemProfile\Tasks\Audio` et `\Pro Audio` — intermédiaire
- `audio-enhancements-disable` — voir section schéma `device-list` ci-dessus —
  intermédiaire
- `audio-exclusive-mode` — voir section schéma `device-list` ci-dessus (mécanisme à
  confirmer techniquement) — intermédiaire — *description mentionne que les
  notifications/sons Discord peuvent être coupés pendant le jeu*

**Périphériques** (nouvelle catégorie)
- `mouse-acceleration-disable` — Désactiver l'accélération de la souris (mouvement 1:1) —
  `HKCU\Control Panel\Mouse` (`MouseSpeed`, `MouseThreshold1`, `MouseThreshold2` = 0) —
  basique
- `mouse-data-queue-size` — Augmenter le buffer d'entrée souris —
  `HKLM\SYSTEM\CurrentControlSet\Services\mouclass\Parameters\MouseDataQueueSize` —
  avancé — *description porte la mention "effet non garanti" (bancs d'essai mitigés)*
- `keyboard-data-queue-size` — Équivalent clavier —
  `HKLM\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters\KeyboardDataQueueSize` —
  avancé — même mention
- `keyboard-repeat-accelerate` — Répétition clavier accélérée —
  `HKCU\Control Panel\Keyboard` (`KeyboardDelay` = 0) — basique
- `usb-thread-priority` — Priorité des threads USB —
  `HKLM\SYSTEM\CurrentControlSet\Services\USBXHCI\Parameters` et `USBHUB3\Parameters`
  (`ThreadPriority` = 31) — avancé — mention "effet non garanti"
- `csrss-priority` — Priorité haute de csrss.exe — avancé — *description doit signaler
  que ce mécanisme date d'une époque antérieure aux protections modernes de csrss.exe
  (Protected Process Light) et que son efficacité sur Windows 11 n'est pas confirmée* ;
  **le handler doit vérifier que la modification a réellement pris effet après
  application et remonter un état honnête si non**, plutôt que d'afficher un succès
  silencieux
- `markc-mouse-fix` — Courbes d'accélération corrigées par DPI (constantes MarkC
  publiées, presets 100/125/150/175/200% embarqués en dur) —
  `HKCU\Control Panel\Mouse` (`SmoothMouseXCurve`/`SmoothMouseYCurve`) — intermédiaire —
  *pour un DPI hors des 5 presets standards, le tweak ne s'applique pas ; la description
  renvoie vers le site MarkC (entrée de guide manuel, Chantier 2) pour un calcul sur
  mesure*

**Latence** (nouvelle catégorie)
- `global-timer-resolution` — Restaurer la résolution timer fine (1ms) pour les jeux —
  `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel\GlobalTimerResolutionRequests`
  = 1 — avancé (Microsoft l'a changé pour l'économie d'énergie ; un process mal codé en
  fond peut augmenter la conso de 10-25%, à mentionner dans la description)
- `dynamic-tick-disable` — Désactiver le Dynamic Tick — handler appelant
  `bcdedit /set disabledynamictick yes` — avancé (impact consommation/chaleur)
- `tsc-sync-policy-enhanced` — `bcdedit /set tscsyncpolicy Enhanced` — avancé, niche
- `hpet-disable` — Désactiver le HPET — `bcdedit /deletevalue useplatformclock` — avancé
  — *description mentionne un effet non consensuel selon les configurations*
- `mmcss-no-lazy-mode` — `HKLM\...\Multimedia\SystemProfile\NoLazyMode` = 1 — avancé —
  mention "non documenté officiellement par Microsoft, effet empirique"
- `irq-priority-tuning` — Priorité IRQ8 (horloge)/IRQ16 (GPU) —
  `HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl` — avancé — mention "effet non
  garanti, mécanisme hérité"

**Productivité** (nouvelle catégorie, volet bureautique)
- `alttab-filter-apps-only` — Filtre Alt+Tab sur les applications seules (pas les onglets
  navigateur) — `HKCU\...\Explorer\Advanced\MultiTaskingAltTabFilter` — basique — *valeur
  exacte à confirmer empiriquement pendant l'implémentation (communauté documente
  1/3/4/5 sans confirmation officielle unique)*
- `snap-assist-flyout-enable` — Activer le flyout Snap Assist —
  `HKCU\...\Explorer\Advanced\EnableSnapAssistFlyout` — basique
- `taskbar-multi-monitor-show-all` — Barre des tâches sur tous les écrans —
  `HKCU\...\Explorer\Advanced\MMTaskbarEnabled`/`MMTaskbarMode`/`MMTaskbarGlomLevel` —
  basique

Total : 41 tweaks automatisés (dont 2 en `device-list`), répartis sur 11 catégories
(7 existantes étendues + 4 nouvelles).

## Comportement UI

Aucun changement de navigation : chaque nouveau tweak s'intègre dans la page de
catégorie existante (grille de toggles), à l'exception du sélecteur de périphérique
requis pour la catégorie Audio (voir section schéma). Les 4 nouvelles catégories créent
chacune un nouvel onglet de catégorie, sur le modèle des 7 existants.

## Hors scope (Chantier 2, spec séparé à venir)

- 12 entrées de guide manuel pour les outils tiers identifiés (Process Lasso,
  ParkControl, NVCleanstall, TCP Optimizer, DNS Jumper, NVIDIA Profile Inspector, O&O
  ShutUp10++, PowerToys FancyZones, Interrupt Affinity Policy Tool, Device Cleanup,
  NVIDIA App).
- 2 entrées de guide manuel pour les mécanismes non confirmés (filtrage barre des tâches
  par bureau virtuel, mémorisation d'emplacement des fenêtres par écran).
- Entrée de guide manuel pour MarkC Mouse Fix hors presets DPI standards.
