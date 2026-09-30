declare const __APP_VERSION__: string

// Injected from package.json so the UI and release package share one version.
export const appVersion = __APP_VERSION__
export const versionLabel = `v${appVersion.replace(/\.0$/, '')}`
