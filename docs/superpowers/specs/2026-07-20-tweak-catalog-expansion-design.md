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

## Tweak par périphérique audio : liste dynamique dédiée (pas de nouveau `kind`)

**Correction d'architecture (post-lecture du moteur existant)** : la conception initiale
prévoyait un nouveau motif générique `kind: "device-list"`, intégré au dispatcher uniforme
`Get-ToggleState`/`Set-ToggleValue` (qui ne connaît aujourd'hui que `registry`, `service`,
`handler`). En étudiant `engine/Engine.ps1` et `renderer/app.js` en détail pendant
l'écriture du plan, il s'avère que ce dispatcher suppose un état *unique par id de
catalogue* — incompatible avec un tweak dont l'état dépend d'un périphérique choisi au
moment de l'usage (`Invoke-GetAllStates`/`Invoke-ResetCategory` itèrent sur le catalogue
sans contexte de périphérique). Le moteur a déjà un motif pour exactement ce cas : les
entrées **sans `kind`** (`type: "startup-list"`, `"bloat-list"`, `"exe-list"` — ex.
`gpu-preference-game`) sont rendues par `renderSpecialWidget()` côté UI et pilotées par
des actions `Invoke-List*`/`Invoke-Add*`/`Invoke-Remove*` dédiées, en dehors du dispatcher
uniforme. Le tweak audio suit ce même motif, avec un nouveau `type: "audio-device-list"` :

```json
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

Fonctionnement moteur (deux nouvelles actions top-niveau, sur le modèle exact de
`ListGpuPrefApps`/`AddGpuPrefApp`) :
- `Invoke-ListAudioDevices` énumère les sous-clés de
  `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\*`, lit le nom
  convivial de chaque périphérique dans sa sous-clé `Properties`
  (valeur `{a45c254e-df1c-4efd-8020-67d146a850e0},14` = `PKEY_Device_FriendlyName`,
  documentée par Microsoft), lit l'état actuel dans sa sous-clé `FxProperties`
  (valeur `{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5` = `PKEY_AudioEndpoint_Disable_SysFx`,
  DWORD, 1 = effets désactivés), et retourne une liste
  `{id: <GUID>, name: <nom lisible>, enhancementsDisabled: <bool>}`.
- `Invoke-SetAudioDeviceEffects` (payload `{deviceId, disabled}`) sauvegarde la clé
  `FxProperties` du périphérique visé puis écrit `{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5`
  à `1` (désactivé) ou `0` (réactivé).
- Les deux mécanismes registre ci-dessus sont documentés par Microsoft (Win32 Core Audio
  API) et confirmés par recoupement indépendant ; ils peuvent être figés tels quels.
- **Rappel de la correction technique déjà actée** : le tweak "mode exclusif audio"
  envisagé au départ a été retiré de ce chantier — son mécanisme registre existe
  (`{b3f8fa53-0004-438e-9003-51a46e139bfc},3`/`,4`) mais nécessite de prendre possession de
  la clé et d'en modifier les ACL (compte SYSTEM), une opération à risque hors du modèle
  "toggle simple" de ce catalogue. Il devient une entrée de guide manuel (Chantier 2) via
  le panneau Son de Windows. Il n'y a donc qu'un seul tweak audio par périphérique dans ce
  chantier (`audio-enhancements-disable`).

Impact UI (`renderer/`) : la page catégorie "Audio" affiche une liste de périphériques
(une ligne par périphérique de sortie, avec son nom et un interrupteur "Effets désactivés"),
exactement comme la liste d'exécutables GPU existante mais avec un interrupteur au lieu
d'un bouton "Retirer" — pas de sélecteur déroulant, pas de nouveau paradigme d'UI.

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
  (même *motif* liste d'exécutables que `gpu-preference-game`, mais **pas la même
  implémentation** : clé de registre différente (`AppCompatFlags\Layers` avec le flag
  `DISABLEDXMAXIMIZEDWINDOWEDMODE`, contre `DirectX\UserGpuPreferences` pour la préférence
  GPU) — les fonctions UI (`renderGpuPrefList`) et moteur (`Invoke-*GpuPrefApp`) existantes
  sont câblées en dur sur la clé GPU et ne peuvent pas être réutilisées telles quelles ;
  ce tweak a donc besoin de son propre `type` de liste spéciale
  (`type: "fullscreen-opt-list"`, sans `kind`) avec ses propres actions moteur dédiées
  (`Invoke-ListFullscreenOptApps`/`Invoke-AddFullscreenOptApp`/
  `Invoke-RemoveFullscreenOptApp`) et sa propre fonction de rendu
  (`renderFullscreenOptList`), construites sur le même modèle que le GPU mais ciblant
  `AppCompatFlags\Layers`) —
  `HKCU\...\AppCompatFlags\Layers` (`DISABLEDXMAXIMIZEDWINDOWEDMODE`) — intermédiaire (ne
  s'applique qu'aux jeux DX9-11)
- `tdr-delay-increase` — Augmenter le délai TDR — `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\TdrDelay`
  — avancé — *description doit mentionner que Microsoft déconseille cette clé aux
  utilisateurs finaux et qu'un vrai problème driver mettra plus longtemps à récupérer*
- `gpu-preemption-disable` — Désactiver la préemption GPU —
  `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler\EnablePreemption` = 0
  (mécanisme recoupé sur deux sources communautaires indépendantes en plus de RayOptimizer,
  mais non documenté officiellement par Microsoft) — avancé — *description porte la
  mention "effet non garanti"*

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
  basique — le réglage est sans effet (inerte) sur un PC sans NPU, donc l'écrire n'est
  jamais risqué ; par clarté d'UX on masque quand même le tweak si aucun NPU n'est détecté.
  **Nouveau champ de schéma symétrique à `guardNoDeviceClass`** : `guardRequiresDeviceClass`
  (guard positif — le tweak n'est activable que si la classe de périphérique est *présente*,
  contrairement à `guardNoDeviceClass` qui bloque quand elle est présente). Détection NPU via
  `Get-PnpDevice -Class 'ComputeAccelerator'`, classe confirmée fonctionnelle aussi bien sur
  Intel Core Ultra (Meteor Lake+) que Snapdragon X (Copilot+ PC ARM).
- `cloud-clipboard-disable` — Désactiver la synchronisation cloud du presse-papiers —
  `HKCU\Software\Microsoft\Clipboard` — basique

**Audio** (nouvelle catégorie)
- `mmcss-audio-priority` — Priorité MMCSS renforcée pour les tâches "Audio"/"Pro Audio" —
  `HKLM\...\Multimedia\SystemProfile\Tasks\Audio` et `\Pro Audio` — intermédiaire
- `audio-enhancements-disable` — voir section "Tweak par périphérique audio" ci-dessus —
  intermédiaire

**Périphériques** (nouvelle catégorie)
- `mouse-acceleration-disable` — Désactiver l'accélération de la souris (mouvement 1:1) —
  `HKCU\Control Panel\Mouse` (`MouseSpeed`, `MouseThreshold1`, `MouseThreshold2` = 0) —
  basique
- `mouse-data-queue-size` — Réduire le buffer d'entrée souris (défaut 100 → 20) —
  `HKLM\SYSTEM\CurrentControlSet\Services\mouclass\Parameters\MouseDataQueueSize` —
  avancé — **correction post-recherche** : la conception initiale disait "augmenter", ce
  qui est l'inverse du tweak communautaire réel (qui réduit la valeur, plage recommandée
  20-60, défaut 100) ; effet contesté (placebo selon certains, réel selon d'autres) —
  *description porte la mention "effet non garanti" (bancs d'essai mitigés)*
- `keyboard-data-queue-size` — Équivalent clavier (défaut 100 → 20) —
  `HKLM\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters\KeyboardDataQueueSize` —
  avancé — même correction, même mention
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
  mesure*. **Nécessite un choix utilisateur (le preset DPI) avant application** : comme le
  tweak audio par périphérique, ce n'est pas un simple interrupteur — c'est un widget
  spécial (`type: "markc-mouse-fix"`, sans `kind`, sur le modèle des entrées de liste
  spéciales) avec un sélecteur de DPI (5 boutons ou liste déroulante) et un état
  activé/désactivé propre.

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
- `alttab-filter-apps-only` — Filtre Alt+Tab sur les applications seules (sans les onglets
  Edge) — `HKCU\...\Explorer\Advanced\MultiTaskingAltTabFilter` = 3 (0 = fenêtres + tous
  les onglets Edge, 1 = + 5 onglets récents, 2 = + 3 onglets récents, 3 = fenêtres
  d'application seules ; valeur confirmée par recherche, nécessite déconnexion/reconnexion
  ou redémarrage pour prendre effet) — basique — *le nom du réglage est trompeur : il ne
  filtre que les onglets Microsoft Edge, pas les onglets d'autres navigateurs*
- `snap-assist-flyout-enable` — Activer le flyout Snap Assist —
  `HKCU\...\Explorer\Advanced\EnableSnapAssistFlyout` — basique
- `taskbar-multi-monitor-show-all` — Barre des tâches sur tous les écrans —
  `HKCU\...\Explorer\Advanced\MMTaskbarEnabled`/`MMTaskbarMode`/`MMTaskbarGlomLevel` —
  basique

Total : 40 tweaks automatisés (dont 1 en liste dynamique par périphérique audio,
sans `kind`), répartis sur 11 catégories
(7 existantes étendues + 4 nouvelles).

## Comportement UI

Aucun changement de navigation : chaque nouveau tweak s'intègre dans la page de
catégorie existante (grille de toggles), à l'exception de la liste de périphériques audio
(voir section "Tweak par périphérique audio" ci-dessus), rendue comme un widget spécial
au même titre que la liste GPU existante. Les 4 nouvelles catégories créent chacune un
nouvel onglet de catégorie, sur le modèle des 7 existants.

## Hors scope (Chantier 2, spec séparé à venir)

- 12 entrées de guide manuel pour les outils tiers identifiés (Process Lasso,
  ParkControl, NVCleanstall, TCP Optimizer, DNS Jumper, NVIDIA Profile Inspector, O&O
  ShutUp10++, PowerToys FancyZones, Interrupt Affinity Policy Tool, Device Cleanup,
  NVIDIA App).
- 2 entrées de guide manuel pour les mécanismes non confirmés (filtrage barre des tâches
  par bureau virtuel, mémorisation d'emplacement des fenêtres par écran).
- Entrée de guide manuel pour MarkC Mouse Fix hors presets DPI standards.
- Entrée de guide manuel pour le mode exclusif audio (4 clics dans le panneau Son de
  Windows, voir section "Tweak par périphérique audio" ci-dessus pour le détail du
  chemin) — retiré de l'automatisation du Chantier 1 après vérification technique
  (nécessiterait une manipulation d'ACL registre à risque).
