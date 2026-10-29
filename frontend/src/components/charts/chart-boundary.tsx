import { Component, type ReactNode } from 'react'

// A failed optional visualization must never hide the financial statement or
// exact values, including when a lazy chunk is unavailable after deployment.
export class ChartBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false }
  static getDerivedStateFromError() { return { failed: true } }
  render() {
    return this.state.failed
      ? <p role="status" className="py-5 text-sm text-muted-foreground">Chart unavailable. Exact values remain below.</p>
      : this.props.children
  }
}
