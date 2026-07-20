const { app, BrowserWindow, ipcMain, shell, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const { execFile } = require('child_process');

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

// Lance Engine.ps1 avec une action nommee. Le payload (si present) est ecrit dans un fichier
// temporaire pour eviter tout probleme d'echappement de guillemets/espaces en ligne de commande.
function runEngine(action, payload) {
  return new Promise((resolve) => {
    let payloadPath = null;
    const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ENGINE_PATH, '-Action', action];

    if (payload !== undefined) {
      payloadPath = path.join(os.tmpdir(), `winoptiapp-${crypto.randomUUID()}.json`);
      fs.writeFileSync(payloadPath, JSON.stringify(payload), 'utf8');
      args.push('-PayloadPath', payloadPath);
    }

    execFile('powershell.exe', args, { windowsHide: true, maxBuffer: 10 * 1024 * 1024 }, (error, stdout, stderr) => {
      if (payloadPath) {
        fs.unlink(payloadPath, () => {});
      }
      if (error) {
        resolve({ ok: false, error: (stderr || error.message || '').toString().trim() });
        return;
      }
      try {
        const trimmed = stdout.trim();
        const jsonStart = trimmed.indexOf('{');
        const jsonText = jsonStart >= 0 ? trimmed.slice(jsonStart) : trimmed;
        resolve(JSON.parse(jsonText));
      } catch (e) {
        resolve({ ok: false, error: `Reponse moteur illisible.\nSTDOUT: ${stdout}\nSTDERR: ${stderr}` });
      }
    });
  });
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1150,
    height: 780,
    minWidth: 950,
    minHeight: 620,
    backgroundColor: '#111318',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });
  win.setMenuBarVisibility(false);
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
}

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// --- IPC : donnees statiques ---
ipcMain.handle('data:getCatalog', async () => {
  return JSON.parse(fs.readFileSync(CATALOG_PATH, 'utf8'));
});

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
ipcMain.handle('engine:call', async (_event, action, payload) => {
  return runEngine(action, payload);
});

// --- IPC : utilitaires ---
ipcMain.handle('shell:openExternalSettings', async (_event, uri) => {
  await shell.openExternal(uri);
  return { ok: true };
});

ipcMain.handle('dialog:pickExecutable', async () => {
  const result = await dialog.showOpenDialog({
    title: 'Choisir un executable de jeu',
    filters: [{ name: 'Executables', extensions: ['exe'] }],
    properties: ['openFile']
  });
  if (result.canceled || result.filePaths.length === 0) return { ok: false };
  return { ok: true, path: result.filePaths[0] };
});
