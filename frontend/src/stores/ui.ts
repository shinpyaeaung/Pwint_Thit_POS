import { create } from 'zustand'

type UIState = { detailsOpen: boolean; toggleDetails: () => void }
export const useUIStore = create<UIState>(set => ({
  detailsOpen: false,
  toggleDetails: () => set(state => ({ detailsOpen: !state.detailsOpen })),
}))
