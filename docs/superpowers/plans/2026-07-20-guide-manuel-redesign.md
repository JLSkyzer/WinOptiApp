# Refonte Guide Manuel (liste -> detail) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer la page Guide manuel (checklist par onglets + cases a cocher) par une vue divisee liste/detail, avec un nouveau modele de donnees enrichi (sections, lien source externe, lien vers tweak automatise associe), une barre de recherche, et une premiere entree sur l'activation manuelle de Widgets/Copilot.

**Architecture:** App Electron existante (main.js + preload.js + renderer/app.js, pas de framework). Pas de suivi "fait/pas fait" (retire), donc plus besoin de persistance d'etat cote main process pour le guide. Le guide garde sa propre taxonomie de categories (distincte de celle des tweaks automatises), reliee ponctuellement via `relatedTweakId`.

**Tech Stack:** Electron 32, JS vanilla (renderer), JSON de donnees statique. Pas de framework de test dans ce depot (`package.json` n'a que `start`/`build`) : la verification se fait par `node --check` (syntaxe) sur les fichiers JS/JSON modifies, puis verification manuelle dans l'app lancee via `npm start`, conformement a la pratique deja etablie sur ce projet.

---

**Note pre-implementation (ecart avec le spec initial) :** Le spec
`docs/superpowers/specs/2026-07-20-guide-manuel-redesign-design.md` indiquait a l'origine
"pas de champ `action`". En regardant le contenu reel de `guide-steps.json`, plusieurs
entrees utilisent deja un champ `action` pour un bouton "Ouvrir Parametres X" (lien direct
`ms-settings:`), fonctionnalite distincte du nouveau `sourceUrl` (lien vers un tutoriel
externe) et qui existait deja avant cette refonte. Ce plan conserve `action` pour ne pas
perdre cette fonctionnalite ; les deux champs sont optionnels et independants.

---

### Task 1: Migrer `data/guide-steps.json` vers le nouveau schema

**Files:**
- Modify: `data/guide-steps.json` (reecriture complete)

- [ ] **Step 1: Remplacer le contenu du fichier**

```json
[
  {
    "id": "nvidia-driver-mode",
    "category": "NVIDIA Panneau de configuration",
    "title": "Mode de gestion d'alimentation -> Performances maximales privilegiees",
    "summary": "Empeche le GPU de sous-cadencer entre deux frames.",
    "sections": [
      { "heading": "Details", "body": "Panneau NVIDIA > Gerer les parametres 3D > Parametres globaux > \"Mode de gestion d'alimentation\". Empeche le GPU de descendre en frequence entre deux frames, essentiel pour la stabilite des FPS." }
    ]
  },
  {
    "id": "nvidia-low-latency",
    "category": "NVIDIA Panneau de configuration",
    "title": "Mode a faible latence -> Ultra",
    "summary": "Reduit la latence input en limitant la file de frames pre-rendues.",
    "sections": [
      { "heading": "Details", "body": "Meme onglet, parametre \"Mode a faible latence\". Reduit la latence input en limitant la file d'attente de frames pre-rendues (equivalent NVIDIA Reflex quand le jeu ne l'implemente pas nativement)." }
    ]
  },
  {
    "id": "nvidia-vsync-off",
    "category": "NVIDIA Panneau de configuration",
    "title": "V-Sync -> Desactive (sauf ecran non G-Sync avec tearing genant)",
    "summary": "Coupe la latence ajoutee par le V-Sync classique.",
    "sections": [
      { "heading": "Details", "body": "Le V-Sync ajoute de la latence input. Sur ecran G-Sync/Free-Sync compatible, laisse le G-Sync gerer la synchronisation et desactive le V-Sync classique." }
    ]
  },
  {
    "id": "nvidia-texture-quality",
    "category": "NVIDIA Panneau de configuration",
    "title": "Filtrage des textures -> Qualite performances / Optimisation prioritaire",
    "summary": "Gagne quelques FPS avec un impact visuel minime.",
    "sections": [
      { "heading": "Details", "body": "Ameliore legerement les FPS avec un impact visuel minime. A ajuster selon le jeu si la nettete des textures lointaines (visibilite cibles) est prioritaire." }
    ]
  },
  {
    "id": "nvidia-sharpening",
    "category": "NVIDIA Panneau de configuration",
    "title": "NVIDIA Image Sharpening (filtre NVIDIA) sur les jeux competitifs",
    "summary": "Ameliore la nettete percue des cibles a distance.",
    "sections": [
      { "heading": "Details", "body": "Active via Alt+F3 (overlay GeForce Experience) ou le panneau NVIDIA par jeu. Ameliore la nettete percue des contours de personnages a distance, directement utile pour la visibilite en FPS." }
    ]
  },
  {
    "id": "nvidia-driver-clean",
    "category": "NVIDIA Panneau de configuration",
    "title": "Installation propre du driver (DDU + dernier Game Ready)",
    "summary": "Reinstallation propre du driver en cas de micro-stutters persistants.",
    "sections": [
      { "heading": "Details", "body": "En cas de micro-stutters persistants : desinstalle le driver actuel avec Display Driver Uninstaller (DDU) en mode sans echec, puis reinstalle le dernier pilote Game Ready (pas Studio) en mode personnalise sans GeForce Experience si non desire." }
    ]
  },
  {
    "id": "bios-xmp",
    "category": "BIOS / UEFI",
    "title": "Activer le profil XMP / EXPO de la RAM",
    "summary": "Fait tourner la RAM a sa vitesse annoncee au lieu de 2133-2666 MHz par defaut.",
    "sections": [
      { "heading": "Details", "body": "Sans XMP, la RAM tourne souvent a 2133-2666 MHz au lieu de sa vitesse annoncee. Impact direct sur les 1% low FPS en CPU-bound. Menu Overclocking / AI Tweaker selon la carte mere." }
    ]
  },
  {
    "id": "bios-resizable-bar",
    "category": "BIOS / UEFI",
    "title": "Activer Resizable BAR / Above 4G Decoding",
    "summary": "Laisse le CPU acceder a toute la VRAM en une fois.",
    "sections": [
      { "heading": "Details", "body": "Permet au CPU d'acceder a la totalite de la VRAM en une fois au lieu de blocs de 256 Mo. Gain FPS variable selon jeu/GPU, sans inconvenient connu sur config recente." }
    ]
  },
  {
    "id": "bios-cstates",
    "category": "BIOS / UEFI",
    "title": "C-States et Power Limits en mode performance (PC fixe branche)",
    "summary": "Reduit les micro-latences de reveil du CPU sur PC fixe branche en permanence.",
    "sections": [
      { "heading": "Details", "body": "Desactiver les etats d'economie d'energie profonds du CPU (C6/C7) ou les regler en mode \"Performance\"/\"Enabled Auto\" selon le fabricant reduit les micro-latences de reveil du CPU. A eviter uniquement si la config chauffe/consomme deja beaucoup au repos." }
    ]
  },
  {
    "id": "bios-fastboot-usb",
    "category": "BIOS / UEFI",
    "title": "Verifier que le mode USB reste en \"Full Initialization\" si peripheriques au demarrage",
    "summary": "Evite les faux peripheriques non detectes au demarrage.",
    "sections": [
      { "heading": "Details", "body": "Le Fast Boot BIOS peut couper l'init USB avant l'OS ce qui retarde la detection clavier/souris au demarrage. Sans impact en jeu, mais evite les faux \"peripherique non detecte\" au boot." }
    ]
  },
  {
    "id": "moniteur-refresh-rate",
    "category": "Moniteur / Affichage",
    "title": "Regler le taux de rafraichissement au maximum de l'ecran",
    "summary": "Verifie que Windows utilise bien le Hz max de l'ecran.",
    "action": { "type": "ms-settings", "target": "ms-settings:display-advanced", "label": "Ouvrir Parametres d'affichage" },
    "sections": [
      { "heading": "Details", "body": "Windows retombe parfois a 60 Hz apres un changement de cable/pilote. Verifier dans Parametres d'affichage avance que le Hz max de l'ecran (144/165/240...) est bien selectionne." }
    ]
  },
  {
    "id": "moniteur-hdr",
    "category": "Moniteur / Affichage",
    "title": "HDR : desactive en competitif, sauf ecran calibre",
    "summary": "Le HDR mal calibre peut degrader la visibilite des cibles sombres.",
    "action": { "type": "ms-settings", "target": "ms-settings:display-hdr", "label": "Ouvrir parametres HDR" },
    "sections": [
      { "heading": "Details", "body": "Le HDR mal calibre delave les couleurs et peut degrader la visibilite des cibles sombres. A garder desactive pour CS2/COD/Battlefield sauf ecran HDR certifie avec calibration verifiee." }
    ]
  },
  {
    "id": "moniteur-scaling",
    "category": "Moniteur / Affichage",
    "title": "Mise a l'echelle geree par l'affichage (GPU) plutot que par Windows",
    "summary": "Le scaling GPU est plus net et plus rapide que le scaling Windows.",
    "sections": [
      { "heading": "Details", "body": "Dans le panneau NVIDIA > Redimensionnement, choisir \"GPU\" avec mise a l'echelle en conservant le ratio d'aspect si tu joues en resolution inferieure a l'ecran natif (meilleure nettete / moins de latence que le scaling Windows)." }
    ]
  },
  {
    "id": "moniteur-cable",
    "category": "Moniteur / Affichage",
    "title": "Verifier le cable utilise (DisplayPort recommande pour Hz eleves)",
    "summary": "Un cable limite peut empecher d'atteindre les Hz eleves annonces.",
    "sections": [
      { "heading": "Details", "body": "Un cable HDMI limite peut empecher d'atteindre 144/240 Hz en pleine resolution. DisplayPort 1.4 est recommande pour la plupart des ecrans gaming modernes." }
    ]
  },
  {
    "id": "cs2-video-settings",
    "category": "CS2",
    "title": "Options video : Basse qualite modeles/textures, ombres minimales",
    "summary": "Reglages video CS2 pour maximiser la visibilite des ennemis.",
    "sections": [
      { "heading": "Details", "body": "Options > Video/Video avancee : Qualite des modeles/textures sur Basse, Qualite des ombres sur Basse. Silhouettes ennemies plus nettes contre des decors moins charges, gain de visibilite classique en CS2." }
    ]
  },
  {
    "id": "cs2-multicore",
    "category": "CS2",
    "title": "Rendu multicoeur active, Anti-Aliasing FXAA ou desactive",
    "summary": "Stabilise les frametimes et garde un anti-aliasing leger.",
    "sections": [
      { "heading": "Details", "body": "Le FXAA lisse legerement l'image sans trop flouter les contours (contrairement au MSAA plus couteux). Le rendu multicoeur ameliore la stabilite des frametimes." }
    ]
  },
  {
    "id": "cs2-launch-options",
    "category": "CS2",
    "title": "Options de lancement Steam : -novid -high",
    "summary": "Options de lancement Steam classiques pour CS2.",
    "sections": [
      { "heading": "Details", "body": "Clic droit CS2 > Proprietes > Options de lancement. -novid saute la video d'intro, -high lance le processus en priorite haute (redondant si Win32PrioritySeparation est deja regle par l'app, mais ne fait pas de mal)." }
    ]
  },
  {
    "id": "cod-render-resolution",
    "category": "Call of Duty",
    "title": "Resolution de rendu dynamique -> desactivee, resolution fixe 100%",
    "summary": "Fige la resolution de rendu pour une nettete constante.",
    "sections": [
      { "heading": "Details", "body": "La resolution dynamique peut faire fluctuer la nettete de l'image selon la charge GPU. En fixant a 100% (ou une valeur fixe adaptee au GPU), la visibilite reste constante." }
    ]
  },
  {
    "id": "cod-filmgrain-fov",
    "category": "Call of Duty",
    "title": "Grain de film desactive, FOV eleve, flou de mouvement desactive",
    "summary": "Coupe les effets qui degradent la lisibilite des cibles en mouvement.",
    "sections": [
      { "heading": "Details", "body": "Ces trois effets degradent directement la lisibilite des cibles en mouvement. A desactiver systematiquement en jeu competitif." }
    ]
  },
  {
    "id": "cod-ondemand-textures",
    "category": "Call of Duty",
    "title": "Diffusion des textures a la demande : verifier l'espace disque et le debit reserve",
    "summary": "Reduit le pop-in de textures qui peut cacher un ennemi.",
    "sections": [
      { "heading": "Details", "body": "Sur SSD, augmenter le cache/debit reserve aux textures reduit le pop-in (textures floues qui se chargent en retard), qui peut cacher un ennemi une fraction de seconde." }
    ]
  },
  {
    "id": "bf-render-scale",
    "category": "Battlefield",
    "title": "Resolution scale a 100%, TAA ou FXAA selon preference nettete/perf",
    "summary": "Arbitrage nettete vs performance pour l'anti-aliasing.",
    "sections": [
      { "heading": "Details", "body": "Le TAA ameliore la stabilite de l'image mais peut legerement flouter les cibles lointaines. Si la visibilite prime sur l'esthetique, privilegier FXAA ou desactiver le TAA." }
    ]
  },
  {
    "id": "bf-motion-blur-dof",
    "category": "Battlefield",
    "title": "Flou de mouvement et profondeur de champ desactives",
    "summary": "Coupe les effets cinematiques qui nuisent a la lecture rapide.",
    "sections": [
      { "heading": "Details", "body": "Comme pour les autres FPS competitifs, ces effets cinematiques nuisent a la lecture rapide des mouvements ennemis." }
    ]
  },
  {
    "id": "bf-fov-hud",
    "category": "Battlefield",
    "title": "FOV eleve (100-110) et HUD simplifie",
    "summary": "Un FOV large ameliore la conscience situationnelle.",
    "sections": [
      { "heading": "Details", "body": "Un FOV plus large ameliore la conscience situationnelle (vision peripherique) au prix d'un leger effet fisheye. A ajuster selon le confort visuel." }
    ]
  },
  {
    "id": "win-game-mode-check",
    "category": "Parametres Windows",
    "title": "Verifier que le Mode Jeu Windows est actif",
    "summary": "Verification manuelle du Mode Jeu deja pilote par l'app.",
    "relatedTweakId": "game-mode",
    "action": { "type": "ms-settings", "target": "ms-settings:gaming-gamemode", "label": "Ouvrir Mode Jeu" },
    "sections": [
      { "heading": "Details", "body": "Parametres > Jeux > Mode Jeu. Deja pilote automatiquement par l'onglet \"Jeux\" de l'app, mais verifiable manuellement ici." }
    ]
  },
  {
    "id": "win-storage-sense",
    "category": "Parametres Windows",
    "title": "Storage Sense : verifier qu'aucun nettoyage automatique agressif n'est programme",
    "summary": "Evite les acces disque impromptus pendant une session de jeu.",
    "action": { "type": "ms-settings", "target": "ms-settings:storagesense", "label": "Ouvrir Storage Sense" },
    "sections": [
      { "heading": "Details", "body": "Storage Sense peut se declencher en arriere-plan et causer des acces disque impromptus. A regler en manuel ou en frequence faible si tu veux zero activite disque surprise en jeu." }
    ]
  },
  {
    "id": "win-focus-assist",
    "category": "Parametres Windows",
    "title": "Assistant de concentration -> Automatique en plein ecran",
    "summary": "Coupe les notifications qui volent le focus en plein ecran.",
    "action": { "type": "ms-settings", "target": "ms-settings:quiethours", "label": "Ouvrir Assistant de concentration" },
    "sections": [
      { "heading": "Details", "body": "Coupe les notifications Windows/apps pendant les sessions de jeu en plein ecran, evite les pop-ups qui volent le focus ou font tomber les FPS un instant." }
    ]
  },
  {
    "id": "win-multiple-displays",
    "category": "Parametres Windows",
    "title": "Un seul ecran actif pendant les sessions competitives (si multi-ecran)",
    "summary": "Reduit la charge de composition desktop en multi-ecran.",
    "action": { "type": "ms-settings", "target": "ms-settings:display", "label": "Ouvrir Parametres d'affichage" },
    "sections": [
      { "heading": "Details", "body": "Un deuxieme ecran actif peut ajouter une charge de composition desktop (DWM) marginale. A desactiver temporairement si tu recherches la derniere fraction de fluidite." }
    ]
  },
  {
    "id": "widgets-copilot-manual",
    "category": "Confidentialite",
    "title": "Reactiver Widgets / Copilot dans la barre des taches",
    "summary": "Si le tweak automatise ne fait pas reapparaitre l'icone, c'est un reglage manuel Windows a changer ici.",
    "relatedTweakId": "widgets-copilot-bing",
    "sourceUrl": "https://support.microsoft.com/fr-fr/windows/utilisation-de-la-barre-des-t%C3%A2ches-dans-windows-11-0657a50f-0cc7-dbfd-ae6b-05020b195b07",
    "sourceLabel": "Voir l'article officiel Microsoft",
    "sections": [
      { "heading": "Pourquoi ce reglage est manuel", "body": "Notre tweak \"Widgets / Copilot / suggestions Bing\" desactive ou restaure exactement l'etat que ta machine avait avant. Il ne force jamais l'affichage d'une icone que tu avais toi-meme masquee dans les Parametres Windows avant d'utiliser l'app. Si l'icone reste invisible apres avoir mis ce tweak sur \"actif\", c'est que Windows la masquait deja avant notre passage : il faut l'activer ici, une fois, manuellement." },
      { "heading": "Etapes", "steps": [
        "Clic-droit sur la barre des taches, puis \"Parametres de la barre des taches\" (ou Parametres > Personnalisation > Barre des taches).",
        "Dans la section \"Elements de la barre des taches\", active le curseur \"Widgets\".",
        "Toujours dans cette page, active le curseur \"Copilot\" si tu veux l'icone Copilot.",
        "Les icones apparaissent immediatement, sans besoin de redemarrer l'Explorateur ni la machine."
      ] }
    ]
  }
]
```

- [ ] **Step 2: Verifier que le JSON est valide**

Run: `node -e "JSON.parse(require('fs').readFileSync('data/guide-steps.json','utf8')); console.log('OK', JSON.parse(require('fs').readFileSync('data/guide-steps.json','utf8')).length)"`
Expected: `OK 28`

---

### Task 2: Retirer la persistance d'etat "fait/pas fait" du guide (main.js + preload.js)

Le guide devient une bibliotheque de reference pure (decision validee) : plus besoin de
stocker un etat "coche/pas coche" par entree cote main process.

**Files:**
- Modify: `main.js:10-26` et `main.js:99-109`
- Modify: `preload.js:7-8`

- [ ] **Step 1: Retirer le chemin et les fonctions d'etat du guide dans `main.js`**

Remplacer :

```javascript
const ENGINE_PATH = path.join(__dirname, 'engine', 'Engine.ps1');
const CATALOG_PATH = path.join(__dirname, 'data', 'tweaks-catalog.json');
const GUIDE_STEPS_PATH = path.join(__dirname, 'data', 'guide-steps.json');

function getGuideStatePath() {
  return path.join(app.getPath('userData'), 'guide-state.json');
}

function loadGuideState() {
  try {
    return JSON.parse(fs.readFileSync(getGuideStatePath(), 'utf8'));
  } catch {
    return {};
  }
}

function saveGuideState(state) {
  fs.writeFileSync(getGuideStatePath(), JSON.stringify(state, null, 2), 'utf8');
}
```

par :

```javascript
const ENGINE_PATH = path.join(__dirname, 'engine', 'Engine.ps1');
const CATALOG_PATH = path.join(__dirname, 'data', 'tweaks-catalog.json');
const GUIDE_STEPS_PATH = path.join(__dirname, 'data', 'guide-steps.json');
```

- [ ] **Step 2: Retirer les handlers IPC `guide:getState` / `guide:setStepChecked`**

Remplacer :

```javascript
ipcMain.handle('data:getGuideSteps', async () => {
  return JSON.parse(fs.readFileSync(GUIDE_STEPS_PATH, 'utf8'));
});

// --- IPC : etat du guide manuel (checklist persistante, cote app, pas moteur PowerShell) ---
ipcMain.handle('guide:getState', async () => {
  return loadGuideState();
});

ipcMain.handle('guide:setStepChecked', async (_event, stepId, checked) => {
  const state = loadGuideState();
  state[stepId] = checked;
  saveGuideState(state);
  return { ok: true };
});

// --- IPC : moteur PowerShell (tout ce qui touche reellement au systeme) ---
```

par :

```javascript
ipcMain.handle('data:getGuideSteps', async () => {
  return JSON.parse(fs.readFileSync(GUIDE_STEPS_PATH, 'utf8'));
});

// --- IPC : moteur PowerShell (tout ce qui touche reellement au systeme) ---
```

- [ ] **Step 3: Retirer les methodes correspondantes de `preload.js`**

Remplacer :

```javascript
contextBridge.exposeInMainWorld('api', {
  callEngine: (action, payload) => ipcRenderer.invoke('engine:call', action, payload),
  getCatalog: () => ipcRenderer.invoke('data:getCatalog'),
  getGuideSteps: () => ipcRenderer.invoke('data:getGuideSteps'),
  getGuideState: () => ipcRenderer.invoke('guide:getState'),
  setGuideStepChecked: (stepId, checked) => ipcRenderer.invoke('guide:setStepChecked', stepId, checked),
  openExternalSettings: (uri) => ipcRenderer.invoke('shell:openExternalSettings', uri),
  pickExecutable: () => ipcRenderer.invoke('dialog:pickExecutable')
});
```

par :

```javascript
contextBridge.exposeInMainWorld('api', {
  callEngine: (action, payload) => ipcRenderer.invoke('engine:call', action, payload),
  getCatalog: () => ipcRenderer.invoke('data:getCatalog'),
  getGuideSteps: () => ipcRenderer.invoke('data:getGuideSteps'),
  openExternalSettings: (uri) => ipcRenderer.invoke('shell:openExternalSettings', uri),
  pickExecutable: () => ipcRenderer.invoke('dialog:pickExecutable')
});
```

- [ ] **Step 4: Verifier la syntaxe des deux fichiers**

Run: `node --check main.js && node --check preload.js`
Expected: aucune sortie (exit code 0)

---

### Task 3: Reecrire `renderGuide()` en vue divisee liste/detail avec recherche

**Files:**
- Modify: `renderer/app.js:14-23` (objet `state`)
- Modify: `renderer/app.js:80-95` (`init()`)
- Modify: `renderer/app.js:485-535` (`renderGuide()`)

- [ ] **Step 1: Adapter l'objet `state`**

Remplacer :

```javascript
  const state = {
    catalog: [],
    statesById: {},
    pending: {},
    guideSteps: [],
    guideState: {},
    currentPage: 'dashboard',
    currentGuideCategory: null,
    isAdmin: true
  };
```

par :

```javascript
  const state = {
    catalog: [],
    statesById: {},
    pending: {},
    guideSteps: [],
    currentPage: 'dashboard',
    currentGuideEntryId: null,
    guideSearchQuery: '',
    guideCollapsedCategories: new Set(),
    isAdmin: true
  };
```

- [ ] **Step 2: Adapter `init()` (retirer le chargement de `guideState`)**

Remplacer :

```javascript
  async function init() {
    const [catalog, guideSteps, guideState, envInfo] = await Promise.all([
      window.api.getCatalog(),
      window.api.getGuideSteps(),
      window.api.getGuideState(),
      window.api.callEngine('GetEnvironmentInfo')
    ]);
    state.catalog = catalog;
    state.guideSteps = guideSteps;
    state.guideState = guideState || {};
    state.isAdmin = envInfo.ok ? !!envInfo.data.isAdmin : true;
    await refreshStates();
    renderAdminBanner();
    renderSidebar();
    renderPage();
  }
```

par :

```javascript
  async function init() {
    const [catalog, guideSteps, envInfo] = await Promise.all([
      window.api.getCatalog(),
      window.api.getGuideSteps(),
      window.api.callEngine('GetEnvironmentInfo')
    ]);
    state.catalog = catalog;
    state.guideSteps = guideSteps;
    state.isAdmin = envInfo.ok ? !!envInfo.data.isAdmin : true;
    await refreshStates();
    renderAdminBanner();
    renderSidebar();
    renderPage();
  }
```

- [ ] **Step 3: Remplacer entierement `renderGuide()` par la vue divisee**

Remplacer la fonction actuelle (de `function renderGuide() {` a son accolade fermante,
juste avant `async function renderRestorePage()`) :

```javascript
  function renderGuide() {
    header('Guide manuel', 'Reglages qui ne peuvent pas etre automatises : panneau NVIDIA, BIOS/UEFI, moniteur, parametres in-game. Coche chaque etape au fur et a mesure.');
    const categories = Array.from(new Set(state.guideSteps.map((s) => s.category)));
    if (!state.currentGuideCategory || !categories.includes(state.currentGuideCategory)) {
      state.currentGuideCategory = categories[0];
    }
    const nav = document.createElement('div');
    nav.className = 'guide-nav';
    categories.forEach((cat) => {
      const tab = document.createElement('div');
      tab.className = 'guide-tab' + (state.currentGuideCategory === cat ? ' active' : '');
      tab.textContent = cat;
      tab.addEventListener('click', () => { state.currentGuideCategory = cat; renderPage(); });
      nav.appendChild(tab);
    });
    contentEl.appendChild(nav);

    const steps = state.guideSteps.filter((s) => s.category === state.currentGuideCategory);
    steps.forEach((step) => {
      const done = !!state.guideState[step.id];
      const row = document.createElement('div');
      row.className = 'guide-step' + (done ? ' done' : '');
      const cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = done;
      cb.addEventListener('change', async () => {
        state.guideState[step.id] = cb.checked;
        await window.api.setGuideStepChecked(step.id, cb.checked);
        row.classList.toggle('done', cb.checked);
      });
      row.appendChild(cb);
      const main = document.createElement('div');
      const title = document.createElement('div');
      title.className = 'guide-step-title';
      title.textContent = step.title;
      main.appendChild(title);
      const desc = document.createElement('div');
      desc.className = 'guide-step-desc';
      desc.textContent = step.description;
      main.appendChild(desc);
      if (step.action && step.action.type !== 'none') {
        const link = document.createElement('span');
        link.className = 'link-btn';
        link.textContent = step.action.label || 'Ouvrir';
        link.addEventListener('click', () => window.api.openExternalSettings(step.action.target));
        main.appendChild(link);
      }
      row.appendChild(main);
      contentEl.appendChild(row);
    });
  }
```

par :

```javascript
  function renderGuide() {
    header('Guide manuel', 'Reglages qui ne peuvent pas etre automatises : panneau NVIDIA, BIOS/UEFI, moniteur, parametres in-game. Selectionne une entree a gauche pour voir le detail complet.');

    const layout = document.createElement('div');
    layout.className = 'guide-layout';
    contentEl.appendChild(layout);

    const listPane = document.createElement('div');
    listPane.className = 'guide-list-pane';
    layout.appendChild(listPane);

    const searchInput = document.createElement('input');
    searchInput.type = 'text';
    searchInput.className = 'guide-search';
    searchInput.placeholder = 'Rechercher un reglage...';
    searchInput.value = state.guideSearchQuery;
    listPane.appendChild(searchInput);

    const listBody = document.createElement('div');
    listPane.appendChild(listBody);

    const detailPane = document.createElement('div');
    detailPane.className = 'guide-detail-pane';
    layout.appendChild(detailPane);

    function refreshDetail() {
      renderGuideDetail(detailPane);
    }

    function refreshList() {
      renderGuideEntryList(listBody, searchInput.value, refreshDetail, refreshList);
    }

    searchInput.addEventListener('input', () => {
      state.guideSearchQuery = searchInput.value;
      refreshList();
    });

    refreshList();
    refreshDetail();
  }

  function renderGuideEntryList(listBody, query, onSelect, refreshSelf) {
    listBody.innerHTML = '';
    const q = query.trim().toLowerCase();
    const categories = Array.from(new Set(state.guideSteps.map((s) => s.category)));

    categories.forEach((cat) => {
      const entries = state.guideSteps.filter((s) => s.category === cat &&
        (!q || s.title.toLowerCase().includes(q) || (s.summary || '').toLowerCase().includes(q)));
      if (!entries.length) return;

      const section = document.createElement('div');
      section.className = 'guide-category-section';
      const collapsed = state.guideCollapsedCategories.has(cat);
      section.classList.toggle('collapsed', collapsed);

      const catHeader = document.createElement('div');
      catHeader.className = 'guide-category-header';
      catHeader.textContent = cat;
      catHeader.addEventListener('click', () => {
        if (state.guideCollapsedCategories.has(cat)) state.guideCollapsedCategories.delete(cat);
        else state.guideCollapsedCategories.add(cat);
        refreshSelf();
      });
      section.appendChild(catHeader);

      const itemsWrap = document.createElement('div');
      itemsWrap.className = 'guide-category-items';
      entries.forEach((entry) => {
        const item = document.createElement('div');
        item.className = 'guide-list-item' + (state.currentGuideEntryId === entry.id ? ' active' : '');
        const title = document.createElement('div');
        title.className = 'guide-list-item-title';
        title.textContent = entry.title;
        item.appendChild(title);
        const summary = document.createElement('div');
        summary.className = 'guide-list-item-summary';
        summary.textContent = entry.summary;
        item.appendChild(summary);
        item.addEventListener('click', () => {
          state.currentGuideEntryId = entry.id;
          onSelect();
          refreshSelf();
        });
        itemsWrap.appendChild(item);
      });
      section.appendChild(itemsWrap);
      listBody.appendChild(section);
    });

    if (!listBody.children.length) {
      const empty = document.createElement('div');
      empty.className = 'empty-state';
      empty.textContent = 'Aucun reglage ne correspond a la recherche.';
      listBody.appendChild(empty);
    }
  }

  function renderGuideDetail(detailPane) {
    detailPane.innerHTML = '';
    const entry = state.guideSteps.find((s) => s.id === state.currentGuideEntryId);
    if (!entry) {
      const empty = document.createElement('div');
      empty.className = 'empty-state';
      empty.textContent = 'Selectionne une entree a gauche.';
      detailPane.appendChild(empty);
      return;
    }

    const title = document.createElement('h2');
    title.className = 'guide-detail-title';
    title.textContent = entry.title;
    detailPane.appendChild(title);

    (entry.sections || []).forEach((sec) => {
      const secTitle = document.createElement('div');
      secTitle.className = 'guide-detail-section-title';
      secTitle.textContent = sec.heading;
      detailPane.appendChild(secTitle);
      if (sec.steps) {
        const ol = document.createElement('ol');
        ol.className = 'guide-detail-steps';
        sec.steps.forEach((s) => {
          const li = document.createElement('li');
          li.textContent = s;
          ol.appendChild(li);
        });
        detailPane.appendChild(ol);
      } else if (sec.body) {
        const p = document.createElement('p');
        p.className = 'guide-detail-body';
        p.textContent = sec.body;
        detailPane.appendChild(p);
      }
    });

    if (entry.action && entry.action.type !== 'none') {
      const link = document.createElement('span');
      link.className = 'link-btn';
      link.textContent = entry.action.label || 'Ouvrir';
      link.addEventListener('click', () => window.api.openExternalSettings(entry.action.target));
      detailPane.appendChild(link);
    }

    if (entry.sourceUrl) {
      const src = document.createElement('span');
      src.className = 'link-btn';
      src.textContent = entry.sourceLabel || 'Voir la source';
      src.addEventListener('click', () => window.api.openExternalSettings(entry.sourceUrl));
      detailPane.appendChild(src);
    }

    if (entry.relatedTweakId) {
      const related = state.catalog.find((e) => e.id === entry.relatedTweakId);
      if (related) {
        const relLink = document.createElement('div');
        relLink.className = 'guide-related-link';
        relLink.textContent = 'Voir le tweak automatise associe -> ' + related.label;
        relLink.addEventListener('click', () => {
          state.currentPage = related.category;
          state.pending = {};
          renderSidebar();
          renderPage();
        });
        detailPane.appendChild(relLink);
      }
    }
  }
```

- [ ] **Step 4: Verifier la syntaxe**

Run: `node --check renderer/app.js`
Expected: aucune sortie (exit code 0)

---

### Task 4: Ajouter/nettoyer les styles CSS pour la vue divisee

**Files:**
- Modify: `renderer/styles.css:323-363` (retirer les regles obsoletes du guide en onglets)
- Modify: `renderer/styles.css` (ajouter les regles de la vue divisee, en fin de fichier)

- [ ] **Step 1: Retirer les regles CSS devenues obsoletes**

Remplacer (les classes `.guide-nav`/`.guide-tab`/`.guide-step*` ne sont plus emises par
`renderGuide()` apres la Task 3) :

```css
.guide-nav {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 22px;
}

.guide-tab {
  padding: 7px 14px;
  border-radius: 999px;
  border: 1px solid var(--border);
  cursor: pointer;
  color: var(--text-dim);
  font-size: 12.5px;
}

.guide-tab.active {
  background: rgba(79,140,255,0.15);
  border-color: var(--accent);
  color: var(--text);
}

.guide-step {
  display: flex;
  gap: 12px;
  padding: 14px 0;
  border-bottom: 1px solid var(--border);
}

.guide-step:last-child { border-bottom: none; }

.guide-step input[type=checkbox] {
  margin-top: 3px;
  width: 16px;
  height: 16px;
  flex: 0 0 auto;
}

.guide-step-title { font-weight: 600; margin-bottom: 3px; }
.guide-step-desc { color: var(--text-dim); line-height: 1.5; font-size: 13px; }
.guide-step.done .guide-step-title { color: var(--text-dim); text-decoration: line-through; }
```

par les nouvelles regles de la vue divisee :

```css
.guide-layout {
  display: flex;
  gap: 20px;
  align-items: flex-start;
}

.guide-list-pane {
  flex: 0 0 340px;
  max-height: calc(100vh - 200px);
  overflow-y: auto;
}

.guide-search {
  width: 100%;
  background: var(--bg-panel);
  border: 1px solid var(--border);
  color: var(--text);
  padding: 8px 12px;
  border-radius: var(--radius);
  font-size: 13px;
  margin-bottom: 14px;
}

.guide-category-section { margin-bottom: 14px; }

.guide-category-header {
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.4px;
  color: var(--text-dim);
  cursor: pointer;
  padding: 6px 4px;
}

.guide-category-header:hover { color: var(--text); }

.guide-category-section.collapsed .guide-category-items { display: none; }

.guide-list-item {
  padding: 9px 10px;
  border-radius: var(--radius);
  cursor: pointer;
  margin-bottom: 3px;
}

.guide-list-item:hover { background: rgba(255,255,255,0.04); }

.guide-list-item.active {
  background: rgba(79,140,255,0.12);
  border-left: 3px solid var(--accent);
}

.guide-list-item-title { font-size: 13px; font-weight: 600; }
.guide-list-item-summary {
  font-size: 12px;
  color: var(--text-dim);
  margin-top: 2px;
  line-height: 1.4;
}

.guide-detail-pane {
  flex: 1;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: 22px 26px;
  min-height: 200px;
}

.guide-detail-title { font-size: 18px; margin: 0 0 16px; }

.guide-detail-section-title {
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.4px;
  color: var(--text-dim);
  margin: 18px 0 6px;
}

.guide-detail-section-title:first-of-type { margin-top: 0; }

.guide-detail-body { line-height: 1.6; font-size: 13.5px; margin: 0; }

.guide-detail-steps {
  margin: 0;
  padding-left: 20px;
  line-height: 1.8;
  font-size: 13.5px;
}

.guide-related-link {
  margin-top: 18px;
  color: var(--accent);
  cursor: pointer;
  font-size: 13px;
}

.guide-related-link:hover { text-decoration: underline; }
```

- [ ] **Step 2: Verifier qu'aucune autre regle du fichier ne reference les classes retirees**

Run: `grep -n "guide-nav\|guide-tab\|guide-step" renderer/styles.css renderer/app.js`
Expected: aucune correspondance (les deux fichiers ne doivent plus contenir ces classes)

---

### Task 5: Verification manuelle bout-en-bout

**Files:** aucun (verification uniquement)

- [ ] **Step 1: Lancer l'application**

Run: `npm start`
Expected: la fenetre WinOptiApp s'ouvre sans erreur dans la console (DevTools si besoin).

- [ ] **Step 2: Verifier la liste du guide**

Cliquer sur "Guide manuel" dans la sidebar. Verifier :
- Les entrees sont groupees par categorie (NVIDIA Panneau de configuration, BIOS / UEFI,
  Moniteur / Affichage, CS2, Call of Duty, Battlefield, Parametres Windows,
  Confidentialite), chacune avec un titre de section cliquable.
- Cliquer sur un titre de categorie la replie/deplie (les entrees disparaissent/reapparaissent).
- Le panneau de droite affiche "Selectionne une entree a gauche" par defaut.

- [ ] **Step 3: Verifier la recherche**

Taper "widgets" dans la barre de recherche. Verifier que seule la categorie
"Confidentialite" avec l'entree "Reactiver Widgets / Copilot..." reste visible, et que
les autres categories disparaissent. Vider le champ : tout reapparait.

- [ ] **Step 4: Verifier la page de detail**

Cliquer sur l'entree "Reactiver Widgets / Copilot dans la barre des taches". Verifier
dans le panneau de droite :
- Le titre complet s'affiche.
- La section "Pourquoi ce reglage est manuel" s'affiche en texte.
- La section "Etapes" s'affiche en liste numerotee (4 etapes).
- Un bouton "Voir l'article officiel Microsoft" est present.
- Un lien "Voir le tweak automatise associe -> Widgets / Copilot / suggestions Bing"
  est present en bas.

- [ ] **Step 5: Verifier les liens sortants**

Cliquer sur "Voir l'article officiel Microsoft" : verifier que le navigateur par defaut
s'ouvre sur la page support.microsoft.com correspondante (et pas dans l'app elle-meme).

Cliquer sur "Voir le tweak automatise associe -> ..." : verifier que l'app navigue vers
la page de categorie "Confidentialite" (tweaks automatises), avec la sidebar mise a jour
sur l'entree correspondante.

- [ ] **Step 6: Verifier une entree sans lien source ni tweak associe**

Cliquer sur une entree quelconque de "CS2" ou "Battlefield". Verifier que le detail
affiche uniquement le titre + la section "Details", sans bouton "Voir la source" ni
lien "tweak associe" (champs absents pour ces entrees).
