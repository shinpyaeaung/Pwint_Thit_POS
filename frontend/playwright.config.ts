import { defineConfig, devices } from '@playwright/test'
export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  // The real authentication service intentionally permits four concurrent hashes.
  workers: 4,
  use: { baseURL: process.env.E2E_BASE_URL || 'http://127.0.0.1:5173', trace: 'retain-on-failure' },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'], channel: 'chrome' } },
    { name: 'webkit', testMatch: ['**/third-party-payments.spec.ts', '**/manual-accounts.spec.ts', '**/purchase-corrections.spec.ts', '**/receiving-groups.spec.ts', '**/warehouse-transfers.spec.ts', '**/landed-pricing.spec.ts', '**/catalog-overlays.spec.ts', '**/shipments.spec.ts', '**/reports.spec.ts', '**/navigation.spec.ts'], use: { ...devices['Desktop Safari'] } },
  ],
})
