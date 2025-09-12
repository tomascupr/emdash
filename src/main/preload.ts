import { contextBridge, ipcRenderer } from 'electron'

// Expose protected methods that allow the renderer process to use
// the ipcRenderer without exposing the entire object
contextBridge.exposeInMainWorld('electronAPI', {
  getVersion: () => ipcRenderer.invoke('app:getVersion'),
  getPlatform: () => ipcRenderer.invoke('app:getPlatform'),
})

// Type definitions for the exposed API
export interface ElectronAPI {
  getVersion: () => Promise<string>
  getPlatform: () => Promise<string>
}

declare global {
  interface Window {
    electronAPI: ElectronAPI
  }
}