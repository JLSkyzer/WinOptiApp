# Chantier 2 : Guide manuel — outils tiers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter 7 fiches d'outils tiers (monitoring/benchmark, latence/input, gestion des process) au Guide manuel, reparties en 3 nouvelles categories, sans aucun changement de code.

**Architecture:** Extension de donnees pure dans `data/guide-steps.json`. La page Guide manuel (`renderer/app.js`, fonction `renderGuideEntryList`) derive deja dynamiquement ses categories par ordre d'apparition dans le tableau JSON — aucune modification de `renderer/app.js`, `main.js` ou `preload.js` n'est necessaire.

**Tech Stack:** JSON de donnees, Node.js pour la validation (`node -e`), Electron (verification manuelle via `npm start`).

**Reference:** Spec complete dans `docs/superpowers/specs/2026-07-21-guide-outils-tiers-design.md`.

---

## Contexte pour l'implementeur

Le fichier `data/guide-steps.json` est un tableau JSON de 28 objets (une entree = un ecran de detail dans le Guide manuel). Chaque objet suit ce schema :

```json
{
  "id": "identifiant-kebab-case-unique",
  "category": "Nom de categorie affiche tel quel (chaine libre)",
  "title": "Titre affiche dans la liste et en haut du detail",
  "summary": "Resume affiche sous le titre dans la liste",
  "action": { "type": "...", "target": "URI ou URL", "label": "Texte du bouton" },
  "sourceUrl": "URL optionnelle vers une source/reference",
  "sourceLabel": "Texte du bouton pour sourceUrl",
  "relatedTweakId": "id-d-un-tweak-du-catalogue-automatise (optionnel)",
  "sections": [
    { "heading": "Titre de section", "body": "Paragraphe de texte" },
    { "heading": "Titre de section", "steps": ["etape 1", "etape 2"] }
  ]
}
```

`action` et `sourceUrl`/`sourceLabel` sont tous les deux optionnels et independants — un objet peut avoir l'un, l'autre, les deux, ou aucun. Le champ `action.type` n'a d'effet special que pour la valeur `"none"` (qui masque le bouton) ; toute autre valeur de `type` est traitee de la meme facon par le rendu (`renderer/app.js:723`) et sert uniquement a documenter l'intention (ex: `"download"` pour un lien de telechargement logiciel, `"link"` pour un lien de documentation/guide). Ne pas confondre avec `action.type: "ms-settings"`, utilise ailleurs dans le fichier pour ouvrir directement un panneau de Parametres Windows — ce n'est pas pertinent ici.

Le fichier ne doit pas etre modifie en dehors du tableau JSON existant : chaque tache ci-dessous ajoute des objets a la fin du tableau, juste avant le `]` final (ligne 270 avant toute modification).

Aucun test automatise n'existe dans ce projet. La verification se fait par :
1. Validite JSON : `node -e "JSON.parse(require('fs').readFileSync('data/guide-steps.json','utf8')); console.log('OK')"`
2. Absence d'id duplique (verifie manuellement a la Task 4, sur la totalite du fichier)

---

### Task 1 : Categorie "Monitoring / Benchmark" (3 fiches)

**Files:**
- Modify: `data/guide-steps.json` (ajout a la fin du tableau, avant le `]` final)

- [x] **Step 1 : Ajouter les 3 entrees JSON suivantes**

Ouvrir `data/guide-steps.json`. Localiser la fin de la derniere entree existante (`"id": "widgets-copilot-manual"`, qui se termine par une ligne `  }` suivie de `]`). Remplacer :

```json
  }
]
```

par (noter la virgule ajoutee apres le `}` de fermeture de `widgets-copilot-manual`) :

```json
  },
  {
    "id": "tool-hwinfo",
    "category": "Monitoring / Benchmark",
    "title": "HWiNFO - monitoring temperatures/frequences/throttle en temps reel",
    "summary": "Detecte les throttles thermiques ou d'alimentation invisibles autrement.",
    "action": { "type": "download", "target": "https://www.hwinfo.com/download/", "label": "Telecharger HWiNFO" },
    "sections": [
      { "heading": "Details", "body": "HWiNFO expose en temps reel les temperatures, frequences et evenements de throttle (thermique ou limite de puissance) du CPU et du GPU. Utile pour diagnostiquer un FPS instable ou des chutes ponctuelles dues a un throttle silencieux que le jeu ne signale pas." },
      { "heading": "Etapes", "steps": [
        "Telecharger la version \"Portable\" sur la page officielle hwinfo.com (pas besoin d'installation).",
        "Au lancement, choisir le mode \"Sensors-only\" pour eviter le rapport materiel complet a chaque demarrage.",
        "Dans la fenetre Sensors, reperer les capteurs de throttle CPU/GPU et les temperatures pour surveiller pendant une session de jeu.",
        "Activer le logging (bouton en bas de la fenetre Sensors) si tu veux analyser les valeurs apres coup dans un fichier CSV."
      ] }
    ]
  },
  {
    "id": "tool-msi-afterburner-rtss",
    "category": "Monitoring / Benchmark",
    "title": "MSI Afterburner + RivaTuner Statistics Server (RTSS) - overclocking GPU et overlay FPS/frametime",
    "summary": "L'overlay de reference pour surveiller FPS, frametime et temperatures en jeu.",
    "action": { "type": "download", "target": "https://www.msi.com/Landing/afterburner/graphics-cards", "label": "Telecharger MSI Afterburner" },
    "sections": [
      { "heading": "Details", "body": "MSI Afterburner (overclocking/monitoring GPU) et RivaTuner Statistics Server (RTSS, overlay en jeu) sont distribues ensemble par le meme installeur MSI, bien que developpes par des equipes differentes. RTSS affiche un overlay configurable (FPS, frametime, temperatures) directement en jeu, standard de facto utilise par la plupart des benchmarkeurs et repris par CapFrameX pour la capture." },
      { "heading": "Etapes", "steps": [
        "Telecharger l'installeur sur la page officielle MSI Afterburner.",
        "Pendant l'installation, verifier que l'option d'installation de RivaTuner Statistics Server est cochee.",
        "Dans Afterburner, onglet \"Monitoring\", cocher les courbes a afficher en overlay (FPS, frametime, temperatures GPU/CPU).",
        "Dans les parametres de RTSS, verifier/regler le raccourci clavier d'affichage de l'overlay en jeu."
      ] }
    ]
  },
  {
    "id": "tool-capframex",
    "category": "Monitoring / Benchmark",
    "title": "CapFrameX - analyse fine des frametimes et des 1% low",
    "summary": "Transforme les captures RTSS en graphiques de stabilite de frametime exploitables.",
    "action": { "type": "download", "target": "https://github.com/CXWorld/CapFrameX/releases", "label": "Telecharger CapFrameX" },
    "sections": [
      { "heading": "Details", "body": "CapFrameX s'appuie sur les captures de RivaTuner Statistics Server pour produire des graphiques de stabilite de frametime, des percentiles (1% low, 0.1% low) et des comparaisons entre plusieurs sessions. Plus technique que HWiNFO ou Afterburner seuls, utile pour valider objectivement l'effet d'un tweak sur la stabilite des FPS plutot que sur la moyenne seule." },
      { "heading": "Etapes", "steps": [
        "Installer prealablement MSI Afterburner + RTSS (necessaire pour la capture).",
        "Telecharger la derniere release CapFrameX depuis la page GitHub officielle du projet.",
        "Lancer CapFrameX et verifier que RTSS est detecte automatiquement (indicateur dans l'interface).",
        "Lancer une capture avec la touche configuree dans RTSS pendant une session de jeu, puis analyser le graphique de frametime dans CapFrameX apres la session."
      ] }
    ]
  },
]
```

**Attention :** cette derniere entree du bloc (`tool-capframex`) est ici suivie d'une virgule avant le `]` car les Tasks 2 et 3 ajouteront des entrees supplementaires apres elle. Le `]` final ne doit rester sans virgule precedente qu'apres la toute derniere entree ajoutee (a la fin de la Task 3).

- [x] **Step 2 : Verifier la validite JSON**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/guide-steps.json','utf8')); console.log('OK')"`
Expected: `OK` (si erreur de parsing, verifier la virgule ajoutee entre `widgets-copilot-manual` et `tool-hwinfo`, et la virgule finale apres `tool-capframex`)

- [x] **Step 3 : Commit**

```bash
git add data/guide-steps.json
git commit -m "Ajouter la categorie Monitoring / Benchmark au guide (HWiNFO, Afterburner+RTSS, CapFrameX)"
```

**Statut d'execution (Task 1) :** DONE. Implementeur (modele haiku) : commit `1ac5c60`. Reviewer spec-compliance : "Spec compliant" (3 entrees exactes, ordre correct, 28 entrees existantes intactes, JSON valide). Reviewer code-quality : "Approuve" (aucun probleme important ; 2 remarques mineures purement cosmetiques sur la longueur du titre `tool-msi-afterburner-rtss` et le style de titre "NomOutil - description", aucune correction requise).

---

### Task 2 : Categorie "Latence / Input" (3 fiches)

**Files:**
- Modify: `data/guide-steps.json` (ajout apres l'entree `tool-capframex` de la Task 1, avant le `]` final)

- [x] **Step 1 : Ajouter les 3 entrees JSON suivantes**

Localiser la fin de l'entree `tool-capframex` ajoutee a la Task 1 (qui se termine par `  },` suivi de `]`). Remplacer :

```json
  },
]
```

par :

```json
  },
  {
    "id": "tool-latencymon",
    "category": "Latence / Input",
    "title": "LatencyMon - detection des latences DPC/ISR causees par les drivers",
    "summary": "Identifie le driver responsable de micro-freezes ou stutters inexpliques.",
    "action": { "type": "download", "target": "https://www.resplendence.com/latencymon", "label": "Telecharger LatencyMon" },
    "sections": [
      { "heading": "Details", "body": "LatencyMon mesure les temps d'execution des routines DPC (Deferred Procedure Call) et ISR (Interrupt Service Routine) de chaque driver charge. Un driver qui bloque le CPU trop longtemps dans ces routines (souvent un driver reseau, audio ou de chipset mal optimise) cause des micro-freezes ou stutters difficiles a diagnostiquer autrement." },
      { "heading": "Etapes", "steps": [
        "Telecharger et installer LatencyMon depuis le site officiel Resplendence.",
        "Lancer l'outil au repos (sans jeu) pendant quelques minutes pour etablir une base, puis relancer une mesure pendant une session de jeu.",
        "Consulter l'onglet des drivers trie par temps d'execution DPC le plus eleve pour identifier le driver le plus problematique.",
        "Mettre a jour le driver identifie (un correctif recent suffit generalement)."
      ] }
    ]
  },
  {
    "id": "tool-nvidia-reflex-analyzer",
    "category": "Latence / Input",
    "title": "NVIDIA Reflex Analyzer - mesure de la latence systeme clic-a-pixel",
    "summary": "Mesure la latence totale entre le clic souris et l'affichage a l'ecran, pas seulement le FPS.",
    "sourceUrl": "https://www.nvidia.com/en-us/geforce/technologies/reflex/",
    "sourceLabel": "Voir la page officielle NVIDIA Reflex",
    "sections": [
      { "heading": "Details", "body": "NVIDIA Reflex Analyzer mesure la latence systeme complete, du clic de souris jusqu'au changement de pixel affiche a l'ecran, contrairement au FPS ou au frametime qui ne mesurent que le rendu GPU. La mesure complete necessite un ecran certifie \"NVIDIA Reflex Analyzer\" et une souris compatible ; sans ce materiel, seule l'activation du mode Reflex (deja couverte par l'entree \"Mode a faible latence\" de ce guide) reste possible, avec un apercu partiel de la latence via l'overlay de performance de l'app NVIDIA." },
      { "heading": "Etapes", "steps": [
        "Verifier que le jeu supporte NVIDIA Reflex (option \"NVIDIA Reflex Low Latency\" dans les parametres graphiques du jeu).",
        "Activer l'overlay de performance via l'app NVIDIA ou GeForce Experience (Alt+R par defaut) pour afficher les statistiques de latence en jeu.",
        "Si un ecran et une souris compatibles Reflex Analyzer sont disponibles, activer la mesure complete clic-a-pixel dans l'overlay pour obtenir la latence systeme totale plutot qu'une estimation partielle."
      ] }
    ]
  },
  {
    "id": "tool-markc-mouse-fix",
    "category": "Latence / Input",
    "title": "MarkC Windows Mouse Acceleration Fix - verification fine de l'acceleration souris",
    "summary": "Verifie et corrige l'acceleration souris au-dela de ce que couvre le tweak automatise.",
    "relatedTweakId": "mouse-acceleration-disable",
    "action": { "type": "link", "target": "https://donewmouseaccel.blogspot.com/", "label": "Voir le guide MarkC" },
    "sections": [
      { "heading": "Details", "body": "Le tweak automatise \"Acceleration souris desactivee\" de l'app regle les 3 valeurs de registre standard (MouseSpeed, MouseThreshold1, MouseThreshold2). Le guide MarkC va plus loin en expliquant comment verifier qu'aucune acceleration residuelle ne subsiste (par exemple via un pilote de souris tiers qui reimpose sa propre courbe d'acceleration en dehors du registre Windows) et comment la neutraliser dans ce cas." },
      { "heading": "Etapes", "steps": [
        "Verifier d'abord que le tweak automatise \"Acceleration souris desactivee\" est active dans l'onglet Peripheriques de l'app.",
        "Consulter le guide MarkC (lien officiel) pour la methode de verification manuelle des valeurs de registre.",
        "Si un logiciel de souris tiers (Logitech G HUB, Razer Synapse, etc.) est installe, verifier dans ses parametres qu'aucune option d'acceleration ou de \"smoothing\" n'est activee en plus des reglages Windows."
      ] }
    ]
  },
]
```

- [x] **Step 2 : Verifier la validite JSON**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/guide-steps.json','utf8')); console.log('OK')"`
Expected: `OK`

- [x] **Step 3 : Commit**

```bash
git add data/guide-steps.json
git commit -m "Ajouter la categorie Latence / Input au guide (LatencyMon, Reflex Analyzer, MarkC Mouse Fix)"
```

**Statut d'execution (Task 2) :** DONE. Implementeur (modele haiku) : commit `3a96e5c`. Reviewer spec-compliance : "Spec compliant" (3 entrees exactes, 34 entrees totales confirmees, `tool-nvidia-reflex-analyzer` sans champ `action` conforme, `tool-markc-mouse-fix` avec `relatedTweakId`+`action.type:"link"` conforme). Reviewer code-quality : "Approuve" (aucun probleme important ; `relatedTweakId` verifie valide contre `mouse-acceleration-disable` dans tweaks-catalog.json ; 2 remarques mineures purement cosmetiques sur la densite du paragraphe Details de l'entree Reflex et sur la premiere utilisation du type `"link"`, aucune correction requise).

---

### Task 3 : Categorie "Gestion des process" (1 fiche)

**Files:**
- Modify: `data/guide-steps.json` (ajout apres l'entree `tool-markc-mouse-fix` de la Task 2, avant le `]` final)

- [x] **Step 1 : Ajouter l'entree JSON suivante**

Localiser la fin de l'entree `tool-markc-mouse-fix` ajoutee a la Task 2 (qui se termine par `  },` suivi de `]`). Remplacer :

```json
  },
]
```

par (noter l'absence de virgule apres le `}` de fermeture de `tool-process-lasso`, car c'est desormais la derniere entree du tableau) :

```json
  },
  {
    "id": "tool-process-lasso",
    "category": "Gestion des process",
    "title": "Process Lasso - automatisation des priorites et affinites CPU",
    "summary": "Regles automatiques de priorite/affinite par process, en complement des tweaks systeme de l'app.",
    "action": { "type": "download", "target": "https://bitsum.com/download/", "label": "Telecharger Process Lasso" },
    "sections": [
      { "heading": "Details", "body": "Process Lasso applique automatiquement des regles de priorite CPU et d'affinite (quels coeurs un process peut utiliser) par nom d'executable, en continu et sans intervention manuelle. Utile pour forcer une priorite haute sur un jeu specifique ou empecher un processus en arriere-plan de monopoliser un coeur, en complement des reglages systeme globaux deja geres par l'app." },
      { "heading": "Etapes", "steps": [
        "Telecharger et installer Process Lasso depuis le site officiel Bitsum.",
        "Dans l'onglet ProBalance, laisser le comportement par defaut (reduction automatique de priorite des process qui consomment trop de CPU en arriere-plan).",
        "Pour un jeu specifique, ajouter une regle dans \"Regles de process\" fixant sa priorite sur \"Haute\" et, si le CPU a beaucoup de coeurs, une affinite excluant un coeur reserve aux taches systeme."
      ] },
      { "heading": "Attention", "body": "L'application automatise deja plusieurs reglages de priorites systeme : Win32PrioritySeparation (priorite CPU renforcee au premier plan), SvchostSplitDynamic (fusion des processus svchost.exe pour reduire l'overhead memoire) et CsrssPriority (priorite du sous-systeme Windows). Si tu utilises Process Lasso en parallele pour gerer manuellement les priorites/affinites d'autres processus (jeux, navigateur...), verifie qu'il n'entre pas en conflit avec ces tweaks : Process Lasso agit au niveau process individuel alors que les tweaks moteur agissent au niveau systeme, donc les deux peuvent normalement cohabiter, mais evite de forcer une priorite Process Lasso qui contredit directement un des tweaks ci-dessus (par exemple, une regle Process Lasso qui repasserait csrss.exe en priorite normale)." }
    ]
  }
]
```

- [x] **Step 2 : Verifier la validite JSON**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/guide-steps.json','utf8')); console.log('OK')"`
Expected: `OK`

- [x] **Step 3 : Commit**

```bash
git add data/guide-steps.json
git commit -m "Ajouter la categorie Gestion des process au guide (Process Lasso + avertissement conflits)"
```

**Statut d'execution (Task 3) :** DONE. Implementeur (modele haiku) : commit `ba06ecb`. Reviewer spec-compliance : "Spec compliant" (entree exacte, 35 entrees totales, 11 categories, aucun doublon). Reviewer code-quality (1er passage) : "Changements demandes" — 2 problemes importants trouves et confirmes independamment (URL de telechargement `https://bitsum.com/download/` en 404 ; description de la section Attention presentant `CsrssPriority` comme un reglage actif alors qu'il est generalement refuse par Windows 11 selon sa propre description dans le catalogue). Correction appliquee via commit `75f672b` (URL remplacee par `https://bitsum.com/processlasso/`, verifiee fonctionnelle ; texte Attention nuance). Reviewer code-quality (2e passage) : "Approuve".

---

### Task 4 : Verification finale

**Files:**
- None (lecture/verification seulement)

- [ ] **Step 1 : Verifier le compte total d'entrees et l'absence d'id duplique**

Run:
```bash
node -e "
const data = JSON.parse(require('fs').readFileSync('data/guide-steps.json','utf8'));
const ids = data.map(e => e.id);
const dupes = ids.filter((id, i) => ids.indexOf(id) !== i);
console.log('Total entrees:', data.length);
console.log('Categories:', Array.from(new Set(data.map(e => e.category))).length);
console.log('Doublons id:', dupes.length ? dupes : 'aucun');
"
```
Expected: `Total entrees: 35`, `Categories: 11`, `Doublons id: aucun`

- [ ] **Step 2 : Verification manuelle dans l'application**

Lancer `npm start` en tant qu'administrateur (necessaire pour le moteur, meme si cette page ne l'utilise pas directement), aller sur la page "Guide manuel", et verifier visuellement :
- Les 3 nouvelles categories ("Monitoring / Benchmark", "Latence / Input", "Gestion des process") apparaissent en bas de la liste des categories.
- Chaque fiche s'ouvre correctement en detail avec ses sections et son bouton de lien (telechargement/source).
- La recherche texte trouve bien "HWiNFO", "Process Lasso", etc.
- Sur la fiche `tool-markc-mouse-fix`, le lien "Voir le tweak automatise associe" pointe vers le tweak "Acceleration souris desactivee" dans la categorie Peripheriques.

Si cette verification ne peut pas etre pilotee via un outil de preview navigateur (limitation deja rencontree au Chantier 1 : les outils `mcp__Claude_Browser__*` ne peuvent pas piloter une fenetre Electron native), documenter cette limitation honnetement dans le statut d'execution plutot que de simuler un succes, et recommander a l'utilisateur de faire cette verification lui-meme.

- [ ] **Step 3 : Commit final si des ajustements ont ete faits pendant la verification**

```bash
git add -A
git commit -m "Chantier 2 : verification finale du guide outils tiers"
```

(Si aucun ajustement n'a ete necessaire, ce commit n'est pas requis.)
