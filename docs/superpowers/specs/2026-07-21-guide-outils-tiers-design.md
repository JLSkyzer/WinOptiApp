# Chantier 2 : Guide manuel — outils tiers

## Contexte

La page "Guide manuel" (`data/guide-steps.json`, rendue par `renderGuide()` dans `renderer/app.js`) couvre actuellement 28 entrées reparties en 8 categories (NVIDIA Panneau de configuration, BIOS/UEFI, Moniteur/Affichage, CS2, Call of Duty, Battlefield, Parametres Windows, Confidentialite). Ce sont des reglages qui ne peuvent pas etre automatises par le moteur PowerShell (`engine/Engine.ps1`) et necessitent une action manuelle de l'utilisateur.

Le Chantier 2 etend ce guide pour couvrir des **outils tiers** recommandes en complement des tweaks automatises et des reglages manuels deja documentes : outils de monitoring/benchmark, de diagnostic de latence, et de gestion des priorites process.

## Contenu

7 nouvelles fiches, reparties en 3 nouvelles categories, ajoutees a la fin de `data/guide-steps.json` (apres les 28 entrees existantes) :

### Categorie "Monitoring / Benchmark"
1. **HWiNFO** — monitoring temperatures/frequences/throttle CPU-GPU en temps reel
2. **MSI Afterburner + RivaTuner Statistics Server (RTSS)** — une seule fiche (installeur commun) : overclocking GPU + overlay FPS/frametime en jeu
3. **CapFrameX** — analyse fine des frametimes/1% low a partir des captures RTSS

### Categorie "Latence / Input"
4. **LatencyMon** — detection des latences DPC/ISR causees par des drivers problematiques
5. **NVIDIA Reflex Analyzer / overlay de latence** — mesure de la latence systeme clic-a-pixel
6. **MarkC Windows Mouse Acceleration Fix** — verification/correction fine de l'acceleration souris, en complement du tweak moteur `mouse-acceleration-disable`

### Categorie "Gestion des process"
7. **Process Lasso** — automatisation des priorites/affinites CPU, avec une section "Attention" dediee (voir ci-dessous)

## Structure des donnees

Aucune modification de schema. Chaque entree reutilise exactement les champs existants de `guide-steps.json` :

```json
{
  "id": "tool-hwinfo",
  "category": "Monitoring / Benchmark",
  "title": "HWiNFO — monitoring temperatures/frequences en temps reel",
  "summary": "Surveille les throttles thermiques invisibles autrement.",
  "action": { "type": "download", "target": "https://www.hwinfo.com/download/", "label": "Telecharger HWiNFO" },
  "sections": [
    { "heading": "Details", "body": "..." },
    { "heading": "Etapes", "steps": ["...", "...", "..."] }
  ]
}
```

Notes :
- `action.type` vaut `"download"` pour ces 7 entrees (au lieu de `"ms-settings"` pour les entrees existantes). Ce champ n'a d'effet sur le rendu que pour la valeur `"none"` (`renderGuideDetail` dans `renderer/app.js:723`) — `"download"` est purement descriptif et ne necessite aucun changement de code.
- `action.target` pointe vers l'URL officielle de telechargement de l'outil. `shell.openExternal` (utilise par `window.api.openExternalSettings`, voir `main.js:89`) ouvre indifferemment une URI `ms-settings:` ou une URL `https://`, donc aucun changement d'IPC/preload n'est necessaire.
- `relatedTweakId` est utilise normalement quand une entree correspond a exactement un tweak automatise existant (ex: `tool-markc-mouse-fix` -> `mouse-acceleration-disable`). Il est en revanche omis sur l'entree Process Lasso, car ce champ ne supporte qu'un seul lien alors que cette fiche doit mentionner plusieurs tweaks existants (voir section suivante) ; cette mention se fait en prose dans une section dediee, a l'image du pattern deja utilise dans l'entree `widgets-copilot-manual`.

### Section "Attention" — Process Lasso

L'entree Process Lasso comporte une section supplementaire :

```json
{ "heading": "Attention", "body": "L'application automatise deja plusieurs reglages de priorites systeme : Win32PrioritySeparation (priorite CPU renforcee au premier plan), SvchostSplitDynamic (fusion des processus svchost.exe pour reduire l'overhead memoire) et CsrssPriority (priorite du sous-systeme Windows). Si tu utilises Process Lasso en parallele pour gerer manuellement les priorites/affinites d'autres processus (jeux, navigateur...), verifie qu'il n'entre pas en conflit avec ces tweaks : Process Lasso agit au niveau process individuel alors que les tweaks moteur agissent au niveau systeme, donc les deux peuvent normalement cohabiter, mais evite de forcer une priorite Process Lasso qui contredit directement un des tweaks ci-dessus (par exemple, une regle Process Lasso qui repasserait csrss.exe en priorite normale)." }
```

## Categorisation

Les 3 nouvelles categories sont ajoutees en fin de fichier JSON, dans cet ordre : "Monitoring / Benchmark", "Latence / Input", "Gestion des process". `renderGuideEntryList` (`renderer/app.js:631`) derive dynamiquement la liste des categories par ordre de premiere apparition dans le tableau (`Array.from(new Set(state.guideSteps.map(s => s.category)))`), donc aucune modification de code n'est requise pour que ces categories apparaissent correctement dans la vue liste/detail.

## Hors scope

- Aucun changement de `renderer/app.js`, `main.js`, `preload.js`, ni des styles CSS — c'est une extension de donnees pure.
- Pas de nouveau champ de schema (pas de tableau `relatedTweakIds`, pas de champ dedie "outil tiers" distinct des entrees existantes).
- Pas de couverture d'autres outils tiers que les 7 listes ci-dessus (DDU est deja mentionne dans l'entree existante `nvidia-driver-clean` et n'est pas duplique ici).

## Verification

- Validite JSON : `node -e "JSON.parse(require('fs').readFileSync('data/guide-steps.json','utf8'))"`
- Aucun id duplique parmi les 35 entrees totales (28 existantes + 7 nouvelles)
- Verification manuelle dans l'app (`npm start`) : les 3 nouvelles categories apparaissent dans la liste, la recherche les trouve, chaque fiche affiche correctement ses sections et son lien de telechargement — avec la meme limitation deja documentee au Chantier 1 (Task 13) que les outils de preview navigateur ne peuvent pas piloter une fenetre Electron native ; cette verification devra etre faite manuellement par l'utilisateur ou via une inspection statique du code equivalente a celle du Chantier 1.
