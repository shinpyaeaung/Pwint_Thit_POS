import { create } from 'zustand'

type UIState = { sidebarOpen: boolean; setSidebarOpen: (open: boolean) => void; detailsOpen: boolean; toggleDetails: () => void }
export const useUIStore = create<UIState>(set => ({
  sidebarOpen: false,
  setSidebarOpen: sidebarOpen => set({ sidebarOpen }),
  detailsOpen: false,
  toggleDetails: () => set(state => ({ detailsOpen: !state.detailsOpen })),
}))
