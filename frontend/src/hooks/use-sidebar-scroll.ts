import { useLayoutEffect, useRef } from 'react'

// Keep each user's menu position across full-page navigation and drawer reopening.
// Storage can be unavailable in private/restricted browsers; navigation still works.
export function useSidebarScroll(userID: string, mobile: boolean) {
  const ref = useRef<HTMLElement>(null)
  const key = `pwint:sidebar:${userID}:${mobile ? 'mobile' : 'desktop'}`
  useLayoutEffect(() => {
    const element = ref.current
    if (!element) return
    try {
      const saved = Number(sessionStorage.getItem(key))
      if (Number.isFinite(saved) && saved >= 0) element.scrollTop = saved
    } catch { /* Optional UI preference. */ }
  }, [key])
  function remember() {
    const element = ref.current
    if (!element?.clientHeight) return
    try { sessionStorage.setItem(key, String(element.scrollTop)) } catch { /* Optional UI preference. */ }
  }
  return { ref, onScroll: remember }
}
