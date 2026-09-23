import { Overlay, type OverlayProps } from './overlay'
export function Drawer(props: OverlayProps & { side?: 'left' | 'right' }) { return <Overlay {...props} drawer /> }
