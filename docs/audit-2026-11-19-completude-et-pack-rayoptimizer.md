# Audit du 2026-11-19 — complétude du catalogue et analyse du pack RayOptimizer

Périmètre : `data/tweaks-catalog.json` (61 tweaks, 11 catégories), `data/guide-steps.json`
(35 fiches), `engine/Engine.ps1`, et le pack `D:\Pack d'Opti RayOptimizer` (358 fichiers,
392 Mo, 25 exécutables ou installeurs `.exe`/`.msi`, 185 fichiers `.reg`).

Légende de fiabilité : **[lu]** constaté en lisant le fichier, **[mesuré]** obtenu par une
commande, **[connu]** connaissance générale non revérifiée ici, **[à vérifier]** à confirmer
avant d'en dépendre.

## 1. Verdict : on n'est pas complet, mais l'essentiel est couvert

Le catalogue couvre bien l'alimentation, le réseau (hors réglages TCP globaux), l'affichage,
les jeux, les services, la confidentialité, l'audio, les périphériques, la latence et la
productivité. Il ne contient **aucune** entrée sur les sujets suivants **[mesuré]** (recherche
textuelle dans le catalogue et le moteur : 0 occurrence) :

| Sujet absent | Source dans le pack | Sûr ? | Proposition |
|---|---|---|---|
| Power Throttling désactivé (PC fixe) | `4 - CPU\Désactive PowerThrottling…reg` **[lu]** : `PowerThrottlingOff=1` | Oui sur PC fixe, à masquer sur portable | `basique`, masqué si batterie détectée |
| Core Parking désactivé | `9\Disable_Core_Parking.reg` **[lu]** modifie `ValueMax` de la clé de métadonnées du réglage, ce qui n'est pas la méthode standard | Oui sur PC fixe | À faire via `powercfg` (min cœurs = 100 %) sur le plan actif, pas via ce `.reg` |
| Raccourcis d'accessibilité (Touches rémanentes, filtrage, bascule) | `7\input lag optimisation.reg` **[lu]** : `Flags="0"` sous `HKCU\Control Panel\Accessibility` | Oui (supprime les pop-ups en plein jeu), à ne pas activer si accessibilité utile | `basique` |
| Réglages TCP globaux (autotuning, RSC, ECN, timestamps) | `6\TCPOptimizer.exe` (le logiciel applique des `netsh`) | Effets débattus **[connu]** | `intermediaire`, à tester avant/après |
| `TrackNblOwner=0` (NDIS) | `6\BufferList\…reg` **[lu]** | Inoffensif, gain non démontré | `avance`, mention « effet non garanti » |
| Hibernation désactivée (`powercfg /h off`) | `9\Disable_Hibernation.reg` **[lu]** | Oui, mais supprime la mise en veille prolongée | `intermediaire` |
| Historique d'activité, localisation, délai de démarrage Explorer, démarrage en arrière-plan d'Edge | non fournis par le pack, usuels en débloat **[connu]** | Oui | Extension de la catégorie confidentialité / démarrage |
| Services Xbox (XblAuthManager, XblGameSave, XboxNetApiSvc, XboxGipSvc) | non fournis | À déconseiller si Game Pass / jeux du Store **[connu]** | `intermediaire` avec avertissement |
| Télémétrie NVIDIA (`NvTelemetryContainer`) | fait par NVCleanstall à l'installation **[lu]** (README) | Oui | Tweak natif, visible seulement si carte NVIDIA |
| Priorité de `csrss.exe` par IFEO | `7\Souris\csrss.exe priority…reg` **[lu]** : `IFEO\csrss.exe\PerfOptions`, appliqué au démarrage | Inconnu sur Windows 11 **[à vérifier]** | Voir section 3 : le handler actuel échoue sur Windows 11 |

Rien d'autre dans le pack ne manque au catalogue : le reste des `.reg` est soit déjà couvert,
soit volontairement exclu (section 2).

## 2. Ce qu'il ne faut surtout pas reprendre du pack

Décision déjà actée dans le spec du 2026-07-20 : aucun tweak à compromis sécuritaire. L'audit
confirme que plusieurs fichiers du pack sont trompeurs **[lu]** :

| Fichier | Ce qu'il fait réellement | Pourquoi l'éviter |
|---|---|---|
| `9\Memory_Management_Advanced.reg` | Contient `FeatureSettingsOverride=3` et `FeatureSettingsOverrideMask=3`, c'est-à-dire la désactivation des mitigations Spectre/Meltdown, sous un nom qui parle de mémoire | Faille de sécurité cachée **[connu]** pour la signification des valeurs |
| `9\Disable_Spectre_Meltdown.reg` | Même chose, explicite | Exclu par décision |
| `9\Disable_Windows_Defender_Realtime.reg` | Coupe la protection en temps réel par stratégie | Exclu par décision |
| `9\Windows_Update_Throttle.reg` | `DoNotConnectToWindowsUpdateInternetLocations=1` : bloque l'accès à Windows Update | Contredit le principe « ne jamais toucher à Windows Update » |
| `1\…\VBS\Désactive VBS.reg` | Coupe VBS/HVCI | Exclu par décision |
| `9\MSI_Mode_GPU.reg` | Nom trompeur : ne touche pas au mode MSI, mais fixe `TdrDelay=60`, `TdrDdiDelay=60` et `TdrLevel=0` | `TdrLevel=0` désactive la détection de blocage du pilote : un freeze GPU devient un gel complet **[connu]** |
| `9\DPC_Timeout_Optimization.reg` | `DpcTimeout=0` | Désactive le chien de garde DPC : un pilote bloqué fige la machine au lieu de provoquer un écran bleu **[connu]** |
| `9\Disable_HPET.reg` | Écrit `Start=4` sous `Enum\ACPI\PNP0103` | Ce n'est pas la méthode (la bonne est `bcdedit`, déjà dans l'app) |
| `9\HPET_Timer_Resolution.reg`, `9\TSC_SyncPolicy.reg` | Valeurs de registre non documentées | Inefficaces ou inconnues **[à vérifier]** |
| `9\Large_Send_Offload.reg`, `9\Network_Adapter_Power_Saving_Off.reg` | Le contenu ne correspond pas au nom (`EnableWsd`, `EnablePMTUDiscovery`…) | Le nom promet autre chose que l'effet |
| `9\USB_Thread_Priority.reg` | `ThreadPriority=31` (priorité maximale) | Déjà dans l'app (`usb-thread-priority`) : voir section 3 |
| `1\…\deleteedge.bat` | Supprime les dossiers d'Edge avec `takeown` + `rd /s /q` | Irréversible sans réinstallation, peut casser les applications qui dépendent de WebView2 |
| `.REVIOS\` (AME Wizard + playbook ReviOS) | Playbook de transformation lourde de Windows | Retire des composants de sécurité, contredit la ligne de l'app |

Autres anomalies **[lu]** : `4 - CPU\…\Meilleur pour Intel\Installation.bat` importe
`Performances Maximum By Lunnyx.pow`, **fichier absent du dossier** (le script échoue en
silence). Les README du pack annoncent des gains chiffrés (« +5-15 % FPS », « -5-20 ms ») qui
ne sont étayés par aucune mesure ; ne pas les reprendre. Le README de `8 - Latency` donne
`0x26` comme valeur par défaut de `Win32PrioritySeparation`, alors que l'app utilise `2`
comme valeur par défaut Windows client.

## 3. Les 61 tweaks actuels : lesquels sont sûrs à activer ou désactiver

Aucun des 61 tweaks ne touche Defender, VBS, les mitigations CPU ou Windows Update **[lu]**
(les mentions de « Defender » dans le catalogue sont des phrases de protection). L'app crée
un point de restauration (`Invoke-CreateRestorePoint`). Tous les tweaks sont réversibles via
l'app. Réserves par tweak :

**Sûrs sans réserve (`basique`)** : plan Performances élevées, réglages réseau (veille de la
carte, Delivery Optimization, DNS), effets visuels, Mode Jeu, GameDVR, Fax, DMWAppPush,
démarrage rapide, délais d'arrêt, Widgets/Copilot/Bing, suggestions, identifiant publicitaire,
Recall, presse-papiers cloud, accélération souris, répétition clavier, productivité (3).

**Sûrs avec une réserve (`intermediaire`)** :
- `network-ipv6-disable` : Microsoft déconseille de désactiver IPv6 **[connu]** ; la variante
  « préférer IPv4 » (`DisabledComponents=0x20`) est moins risquée. À changer.
- `msi-mode`, `msi-mode-network` : modifient des clés par périphérique ; un pilote qui gère
  mal le MSI peut donner un écran noir au démarrage. Réversible depuis le mode sans échec.
  Point de restauration recommandé.
- `usb-selective-suspend`, `power-plan-ultimate`, `cpu-boost-aggressive`,
  `global-timer-resolution` : consommation et chaleur, à réserver au PC fixe.
- `hags`, `fullscreen-optimizations-disable` : effet variable selon pilote et jeu, réversibles.
- `service-diagtrack`, `werror-reporting-disable`, `background-apps`, `service-bluetooth` :
  sûrs ; le Bluetooth est déjà protégé par une vérification matérielle.

**À traiter avec prudence (`avance`)** :
- `mouse-data-queue-size`, `keyboard-data-queue-size` (100 → 20) : effet non démontré, et une
  file plus petite peut **perdre des évènements** avec une souris à 4–8 kHz. Le README du pack
  dit l'inverse (valeur plus haute pour éviter les pertes). Recommandation : ne pas activer
  avec une souris au-delà de 1000 Hz, ou retirer le tweak.
- `usb-thread-priority` (31) : priorité temps réel pour les threads USB, risque d'affamer
  d'autres threads sous charge USB.
- `csrss-priority` : le handler fixe la priorité à l'exécution, ce que Windows 11 refuse
  (l'app le signale déjà). La voie du pack (`IFEO\csrss.exe\PerfOptions`, appliquée au
  redémarrage, comme déjà fait pour `SearchIndexer` et `TiWorker`) est à tester.
- `gpu-preemption-disable` : clé non documentée, risque d'instabilité du pilote.
- `dynamic-tick-disable`, `tsc-sync-policy-enhanced`, `hpet-disable` : modifient la
  configuration de démarrage via `bcdedit`. Réversibles, mais à ne pas empiler sans mesurer.
- `irq-priority-tuning`, `mmcss-no-lazy-mode` : mécanismes hérités ou non documentés, effet
  probablement nul.
- `tdr-delay-increase` : sûr, mais retarde la récupération d'un vrai plantage du pilote.

## 4. Exécutables du pack : analyse

Méthode : signature Authenticode, version et éditeur, empreinte SHA-256, comparaison avec les
fonctions natives de l'app. **L'analyse antivirus n'a pas pu être faite** : Microsoft Defender
est désactivé sur cette machine (`MpCmdRun` : « Product/Feature disabled ») **[mesuré]**. Les
binaires non signés ne sont donc pas vérifiés par un antivirus ; leurs empreintes sont en
annexe pour un contrôle sur VirusTotal ou contre les versions officielles.

Doublons **[mesuré]** : `intPolicy_x64.exe` (×2, même empreinte), `ButtonExtended.dll` (×2),
`parkcontrolsetup64.exe` (deux versions : 5.2.1.4 à la racine, 5.0.2.18 dans le dossier Intel),
Process Lasso (portable 10.1.0.42 de 2021 et installeur 14.0.1.10).

| # | Outil | Signature | Fonction unique ou déjà native dans l'app ? |
|---|---|---|---|
| 1 | Process Lasso | Valide (Bitsum) | Unique, déjà en fiche du guide |
| 2 | ParkControl | Valide (Bitsum) | Le Core Parking se règle en natif avec `powercfg` |
| 3 | QuickCPU 4.10 | Valide (CoderBag) | Chevauche plans d'alimentation et boost CPU |
| 4 | O&O ShutUp10++ | Valide (O&O) | Chevauche les tweaks de confidentialité |
| 5 | Opera GX installeur | Valide (Opera) | Pas un outil d'optimisation |
| 6 | Ultimate Windows Tweaker 5.1 (et 4.8) | Non signé | Interface de réglages registre, redondant |
| 7 | Win11Debloat (script) | Script ouvert | Redondant avec le débloat natif |
| 8 | Tweak-SSD | Valide (Totalidea) | Obsolète (Windows 7 à 10) |
| 9 | InSpectre | Valide (GRC) | Lecture/bascule des mitigations, exclu par décision |
| 10 | intPolicy_x64 | Valide (Microsoft) | Affinité d'interruptions, faisable en registre |
| 11 | AutoGpuAffinity (zip) | Non vérifiable | Unique (banc d'essai de l'affinité GPU) |
| 12 | DDU 18.0.7.4 | Valide (Wagnardsoft) | Unique, déjà cité dans le guide |
| 13 | NVCleanstall 1.16.0 | Valide (TechPowerUp) | Unique |
| 14 | NVIDIA Profile Inspector 2.4.0.4 + 2 profils `.nip` | Non signé | Unique |
| 15 | NVIDIA app beta 10.0.2.210 | Valide (NVIDIA) | Installeur de 141 Mo, version bêta datée |
| 16 | DnsJumper 2.2 | Signature non validée (Sordum) | Redondant avec `dns-fast` |
| 17 | TCP Optimizer 4.1.1 | Non signé | Redondant avec des `netsh` natifs |
| 18 | DeviceCleanup 1.2.1 | Signature non validée (Uwe Sieber) | Faisable avec `pnputil` |
| 19 | MSI_util_v3 | Non signé, sans éditeur | Déjà natif (`msi-mode`) |
| 20 | PowerSettingsExplorer | Non signé, sans éditeur | Faisable avec `powercfg -attributes` |
| 21 | SetTimerResolution | Non signé, aucune métadonnée | Équivalent natif possible |
| 22 | MeasureSleep | Non signé, aucune métadonnée | Mesure uniquement |
| 23 | AME Wizard + playbook ReviOS | Non signé | Contredit la ligne sécurité |
| 24 | deleteedge.bat | Script | Destructeur |

Les licences de redistribution ne sont pas vérifiées ici. Pour un usage personnel ce n'est pas
un sujet ; pour une diffusion publique de l'app, chaque éditeur (Bitsum, Wagnardsoft,
TechPowerUp, O&O, GRC…) est à contrôler **[à vérifier]**. Embarquer ces binaires ferait aussi
passer l'exécutable portable de quelques dizaines de Mo à plusieurs centaines.

Les décisions de l'utilisateur sur chaque outil sont consignées dans la section 5.

## 5. Décisions de l'utilisateur

Décisions prises le 2026-11-19, une par outil. **Aucun exécutable du pack n'est embarqué dans
l'app.** Le playbook ReviOS (`.apbx`) n'a pas pu être ouvert avec `unzip` (format non
identifié, probablement protégé) : il n'a pas été audité.

| Outil | Décision | Suite à donner |
|---|---|---|
| Process Lasso | Lien officiel seulement | Fiche `tool-process-lasso` déjà présente, rien à faire |
| ParkControl | Tweak natif, pas d'exe | Ajouter un tweak Core Parking via `powercfg` (PC fixe) |
| QuickCPU | Ne pas utiliser | Aucune |
| O&O ShutUp10++ | Lien officiel seulement | Ajouter une fiche de guide avec lien ; compléter les tweaks de confidentialité natifs |
| Opera GX | Ne pas utiliser | Aucune |
| Ultimate Windows Tweaker (4.8 et 5.1) | Ne pas utiliser | Aucune |
| Win11Debloat | Ne pas utiliser | Aucune |
| Tweak-SSD | Ne pas utiliser | Aucune |
| InSpectre | Ne pas utiliser | Aucune |
| intPolicy_x64 | Ne pas embarquer | Pas de réécriture demandée pour l'instant |
| AutoGpuAffinity | Lien officiel seulement | Ajouter une fiche de guide avec lien vers le dépôt de l'auteur |
| DDU | Lien officiel seulement | Mettre à jour la fiche `nvidia-driver-clean` avec un lien vers la dernière version |
| NVCleanstall | Lien officiel seulement | Ajouter une fiche de guide avec lien |
| NVIDIA Profile Inspector (+ 2 `.nip`) | Lien officiel seulement | Fiche de guide avec lien ; auditer les `.nip` et proposer les réglages utiles pour la fiche NVIDIA |
| NVIDIA app bêta | Ne pas utiliser | Aucune |
| DnsJumper | Choix de DNS natif, pas d'exe | Étendre `dns-fast` (Cloudflare, Google, Quad9, retour au DNS d'origine) |
| TCP Optimizer | Tweaks `netsh` natifs, pas d'exe | Ajouter les tweaks TCP (autotuning, RSC, ECN, timestamps), marqués « effet à tester » |
| DeviceCleanup | Ne pas utiliser | Aucune |
| MSI_util_v3 | Ne pas utiliser | Aucune (déjà natif) |
| PowerSettingsExplorer | Ne pas utiliser | Aucune |
| SetTimerResolution | Ne pas utiliser | Aucune (la réécriture native proposée a été refusée) |
| MeasureSleep | Mesure native dans l'app | Ajouter un test de précision du timer avant/après |
| AME Wizard + ReviOS | Ne pas utiliser | Aucune |
| deleteedge.bat | Ne pas utiliser | Aucune |

### Réalisé le 2026-11-19 : tweaks natifs (catalogue 61 → 73 entrées)

Ajoutés : `power-throttling-disable` (bloqué si batterie), `core-parking-disable`,
`hibernation-disable`, `tcp-rsc-disable`, `dns-google`, `dns-quad9` (avec `dns-fast` ces trois
DNS sont exclusifs et partagent la mémoire du DNS d'origine), `accessibility-shortcuts-disable`
(coupe seulement le raccourci clavier, bit 0x04 de `Flags`), `activity-history-disable`,
`location-disable`, `edge-background-disable`, `explorer-startup-delay-remove`, et un widget
« Mesurer la précision du timer » dans la catégorie Latence (action moteur `MeasureTimer`).

Volontairement **non ajoutés** (gain non démontré ou risque) : `TrackNblOwner` (champ de
débogage NDIS), autotuning/ECN/timestamps TCP (débit dégradé ou gain négligeable), services
Xbox (casse Game Pass et le Store), télémétrie NVIDIA (service absent des pilotes récents,
**[à vérifier]**).

Vérifié : syntaxe PowerShell sans erreur, `GetAllStates` renvoie 67 états dont les 12 nouveaux
cohérents avec la machine (Core Parking, hibernation et raccourcis déjà coupés), 16 tests
unitaires des helpers en clé de registre temporaire, mesure du timer exécutée. **Non vérifié** :
application réelle de chaque tweak (aucun réglage de la machine n'a été modifié) et affichage
dans la fenêtre Electron.

### Réalisé le 2026-11-19 : correction des tweaks à risque (catalogue : 74 entrées)

- `network-ipv6-disable` est **retiré** et remplacé par `network-prefer-ipv4`
  (`DisabledComponents=0x20`, méthode documentée Microsoft KB929852 **[connu]**) : IPv6 reste actif.
- `mouse-data-queue-size`, `keyboard-data-queue-size`, `usb-thread-priority` sont **retirés**
  (aucun gain démontré, perte d'évènements ou famine de threads plausible **[connu]**).
- Un tweak `retired: true` n'est affiché que s'il est **actuellement actif**, pour que tu puisses
  le désactiver ; la remise à zéro de catégorie continue de le traiter. Sur cette machine les
  quatre sont à « off », donc invisibles.
- `csrss-priority` passe de l'élévation à chaud (refusée par Windows 11) à
  `Image File Execution Options\csrss.exe\PerfOptions\CpuPriorityClass=3`, appliqué au prochain
  démarrage. Effet non garanti **[à vérifier : mesurer l'input lag avant/après]**.
- Non traité : `gpu-preemption-disable` (clé non documentée, laissé en `avance` avec sa mention
  d'effet non garanti).

Reste à planifier : cinq fiches de guide avec lien (O&O ShutUp10++, AutoGpuAffinity,
NVCleanstall, NVIDIA Profile Inspector, lien DDU à jour).

## Annexe — empreintes SHA-256 du pack

﻿
| Fichier | Taille (Ko) | Signature | SHA-256 |
|---|---|---|---|
| .REVIOS/AME-Wizard-Beta.exe | 150127 | NotSigned | `A637F32B64E1493B315DB9139065105656C84518DCA20CE3B18C89750EE40C82` |
| .REVIOS/Revi-PB-24.06.apbx | 1207 | n/a | `BEE7BA90FCE417EC66D35588ADD2F1B0B7972F9959C5A439E2BA5101397E21DE` |
| 1 - Opti Windows/Désinstalle mirosoft edge/OperaGXSetup.exe | 3505 | Valid | `8EEA71B558A9EE895782AFD3B62DF3C4E1024E4D68BB6551C61B93A4D8573414` |
| 1 - Opti Windows/Suprime les Bloatware et la Telemetry/OOSU10.exe | 1888 | Valid | `7335914D30D8EDE5431C4BA32F56A79A397A6F38BFD44E90F62324F63AFEDA65` |
| 1 - Opti Windows/UWT 4.8 pour windows 10/ButtonExtended.dll | 26 | NotSigned | `11692A5C5001628E294AE9E1146ABD4B4470E81F21883F80A7AF7FE6D197D44B` |
| 1 - Opti Windows/UWT 4.8 pour windows 10/Ultimate Windows Tweaker 4.8.exe | 660 | NotSigned | `B25B8E40616136045F021A9AC1E2143B3460CAED08C01606820CA4FA4107E5F2` |
| 1 - Opti Windows/UWT 5.1 pour windows 11/ButtonExtended.dll | 26 | NotSigned | `11692A5C5001628E294AE9E1146ABD4B4470E81F21883F80A7AF7FE6D197D44B` |
| 1 - Opti Windows/UWT 5.1 pour windows 11/Ultimate Windows Tweaker 5.1.exe | 678 | NotSigned | `DCB60E763CC3DB3D95135FA080589ECDB1535FDEBC0F8C27541B0D03F97F166C` |
| 2 - Stockage/Optimiser SSD/tweak-ssd-for-7-8-and-10_2-0-70_fr_419850.exe | 13684 | Valid | `68FF9B62D5789890FF32ABE5669C26AFE1E7F28C4DAA068ABF2FDEE5B8C46B79` |
| 4 - CPU/InSpectre.exe | 126 | Valid | `72415C602AFD60B5153FD5E44D238B975FD8F57D8DDE06968FBC9BB13F170FAE` |
| 4 - CPU/Parametre d'alimentation/Meilleur pour Intel/parkcontrolsetup64.exe | 1111 | Valid | `82536B6FAA2106C563C112DB1F35713F8CCF0380A01C63D197DB288B4C280E43` |
| 4 - CPU/processlassosetup64.exe | 2535 | Valid | `25ACE20639977320F2E7432AF2532D0607E29087D4496EF1BDA97CA8D165CB3F` |
| 5 - GPU/Affinity/AutoGpuAffinity.zip | 12990 | n/a | `BBA7E57058B3FE84E2C0578BF07A4816CEE779D7253859FCB9CE99B493E645A7` |
| 5 - GPU/Affinity/intPolicy_x64.exe | 32 | Valid | `EFB1CA93C6BEEF992B59AD8B4C8B83C418B418040514D8597D9E4CA0686B0E46` |
| 5 - GPU/Clean install pilote graphique/DDU v18.0.7.4/Display Driver Uninstaller.exe | 1164 | Valid | `E4CAA12DBD94E419A2D0ABA77709364470659F62385F53DA475B274EBB68CDB7` |
| 5 - GPU/Clean install pilote graphique/NVCleanstall_1.16.0.exe | 3843 | Valid | `EFECB17D9D73082BF28A6E7C6BB87A81C65A59B2D4D14251678DA3CFFA6A12A1` |
| 5 - GPU/Nvidia/nvidiaProfileInspector/NVIDIA_app_beta_v10.0.2.210.exe | 141769 | Valid | `5C1499F8800FB45CF301E4D3F4A77602ACFF5516B6415A380532DB358475FF79` |
| 5 - GPU/Nvidia/nvidiaProfileInspector/nvidiaProfileInspector.exe | 536 | NotSigned | `1233487EA4DB928EE062F12B00A6EDA01445D001AB55566107234DEA4DC65872` |
| 6 - Internet & Ping/DnsJumper/DnsJumper.exe | 885 | UnknownError | `7E221E7967570B0DECA8E1C4F23ED9E39423DCC0733337BCB6E2C08B3B7B9BA1` |
| 6 - Internet & Ping/TCPOptimizer.exe | 668 | NotSigned | `0A49DC0D2CE725AF347DF632539B70AFCFD22B38E285920B515143332A5511E9` |
| 7 - Périphériques/Supprimer périphériques non utilisées/x64/DeviceCleanup.exe | 75 | UnknownError | `76ECFDA929285DBE75C877455332BBF30218269C03700B4E884345CF9B3BA6B5` |
| 8 - Latency tweak/intPolicy_x64.exe | 32 | Valid | `EFB1CA93C6BEEF992B59AD8B4C8B83C418B418040514D8597D9E4CA0686B0E46` |
| 8 - Latency tweak/MSI_util_v3/MSI_util_v3.exe | 38 | NotSigned | `E1C02DF86676D04ED75BA6303B53B61C15ADB6AEC672AC349C2F06454A594E1E` |
| 8 - Latency tweak/PowerSettingsExplorer.exe | 96 | NotSigned | `800DF13B14449E0A00A02764586E0EA6EC19D0F2EFB8D778E0DAAEE3585F16C5` |
| 8 - Latency tweak/Timer Resolution/MeasureSleep.exe | 138 | NotSigned | `5B4B139AC7318987EECDF101C0305A868AB21171076BA194AF293C576AC0DB0D` |
| 8 - Latency tweak/Timer Resolution/SetTimerResolution.exe | 136 | NotSigned | `FE3CDBE2E332E48921FFA2A9697A66F71472D878154BA331D12ADC7E7C767A2B` |
| parkcontrolsetup64.exe | 1120 | Valid | `4A29C42A5D5332FF0813A0012B77EA33D2E7F815BEF93F49AAB1A8AE1951F095` |
| Process Lasso.exe | 2370 | Valid | `B2EFCC14C9CF2486C61BB64A19DEF1AD710660A20B8C2300AB732CBC5AF56C37` |
| QuickCpuSetup-4.10.0.0-x64.msi | 34840 | Valid | `6521BED985B7889461A8BF049248B5CC2561BB5DE87E96DA351131BACC1EAB0F` |
