import { expect, type Page } from '@playwright/test'
export const testPassword = process.env.E2E_PASSWORD!
export const owner = process.env.E2E_USERNAME!
export const staff = process.env.E2E_STAFF_USERNAME!
export async function signIn(page: Page, username = owner, password = testPassword) {
  if (!username || !password) throw new Error('Use make test-e2e to run with disposable test accounts.')
  await page.goto('/login')
  await page.getByLabel('Username', { exact: true }).fill(username)
  await page.getByLabel('Password', { exact: true }).fill(password)
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Sign out' })).toBeVisible()
}
