import { test, expect } from '@playwright/test'
import { signIn } from './session'
test.beforeEach(async ({ page }) => { await signIn(page) })

test('connects the real frontend to the API and PostgreSQL', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', error => errors.push(error.message))
  await page.goto('/')
  await expect(page.getByRole('heading', { name: /a solid start/i })).toBeVisible()
  await expect(page.getByRole('status')).toHaveText('All systems connected. The foundation is ready.')
  await expect(page.getByText('PostgreSQL is connected')).toBeVisible()
  await page.getByRole('button', { name: 'Check again' }).click()
  await expect(page.getByRole('button', { name: 'Check again' })).toBeEnabled()
  await page.getByRole('button', { name: 'Foundation details' }).click()
  await expect(page.getByText('MMK base currency')).toBeVisible()
  expect(errors).toEqual([])
})

test('shows outage and recovers without a page reload', async ({ page }) => {
  await page.route('**/api/v1/health', route => route.fulfill({ status: 503, contentType: 'application/json', body: '{"error":{"code":"database_unavailable","message":"Database connection is unavailable."}}' }))
  await page.goto('/')
  await expect(page.getByRole('status')).toContainText('Database connection is unavailable')
  await expect(page.getByText('PostgreSQL is connected')).not.toBeVisible()
  await page.unroute('**/api/v1/health')
  await page.getByRole('button', { name: 'Check again' }).click()
  await expect(page.getByRole('status')).toHaveText('All systems connected. The foundation is ready.')
})

test('fits a mobile viewport', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 })
  await page.goto('/')
  await expect(page.getByRole('status')).toContainText('All systems connected')
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
})
