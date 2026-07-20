const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  callEngine: (action, payload) => ipcRenderer.invoke('engine:call', action, payload),
  getCatalog: () => ipcRenderer.invoke('data:getCatalog'),
  getGuideSteps: () => ipcRenderer.invoke('data:getGuideSteps'),
  openExternalSettings: (uri) => ipcRenderer.invoke('shell:openExternalSettings', uri),
  pickExecutable: () => ipcRenderer.invoke('dialog:pickExecutable')
});
