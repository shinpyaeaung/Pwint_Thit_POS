import { test, expect } from '@playwright/test'
import { signIn, owner, staff, testPassword } from './session'

test('redirects signed-out visitors and restores a secure session after reload', async ({ page }) => {
  await page.goto('/users')
  await expect(page).toHaveURL(/\/login\?next=/)
  await page.getByLabel('Username', { exact: true }).fill(owner)
  await page.getByLabel('Password', { exact: true }).fill(testPassword)
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page).toHaveURL(/\/users$/)
  await expect(page.getByRole('heading', { name: 'Users & access' })).toBeVisible()
  await page.screenshot({ path: '/tmp/pwint-auth-users.png', fullPage: true })
  await page.reload()
  await expect(page.getByRole('heading', { name: 'Users & access' })).toBeVisible()
  expect(await page.evaluate(() => localStorage.length)).toBe(0)
  expect(await page.evaluate(() => document.cookie)).not.toContain('pwint_session')
  await page.getByRole('button', { name: 'Sign out' }).click()
  await expect(page.getByRole('heading', { name: 'Sign in to your workspace' })).toBeVisible()
  expect((await page.request.get('/api/v1/auth/me')).status()).toBe(401)
  await page.goto('/users')
  await expect(page).toHaveURL(/\/login/)
})

test('rejects incorrect credentials', async ({ page }) => {
  await page.goto('/login')
  await page.getByLabel('Username', { exact: true }).fill(owner)
  await page.getByLabel('Password', { exact: true }).fill('wrong password')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page.getByRole('alert')).toHaveText('Invalid username or password.')
  expect((await page.request.get('/api/v1/auth/me')).status()).toBe(401)
})

test('staff cannot access restricted pages or APIs', async ({ page }) => {
  await signIn(page, staff)
  await expect(page.getByRole('link', { name: 'Users & access' })).not.toBeVisible()
  await page.goto('/users')
  await expect(page.getByRole('heading', { name: 'Access restricted' })).toBeVisible()
  expect((await page.request.get('/api/v1/users')).status()).toBe(403)
  expect((await page.request.get('/api/v1/permissions')).status()).toBe(403)
})

test('owner creates staff and grants then revokes access', async ({ page, browser }) => {
  await signIn(page)
  await page.goto('/users')
  const name = `staff-${Date.now()}`
  await page.getByLabel('Display name', { exact: true }).fill('New Operator')
  await page.getByLabel('Username', { exact: true }).fill(name)
  await page.getByLabel('Initial password', { exact: true }).fill(testPassword)
  await page.getByRole('button', { name: 'Create Staff Admin' }).click()
  await expect(page.getByText('Staff account created.')).toBeVisible()
  await page.getByRole('button', { name: `Manage permissions for ${name}` }).click()
  const editor = page.getByRole('region', { name: `Permissions for ${name}` })
  await editor.getByRole('checkbox', { name: /^users.manage/ }).check()
  await editor.getByRole('button', { name: 'Save permissions' }).click()
  await expect(editor).not.toBeVisible()
  const context = await browser.newContext({ baseURL: process.env.E2E_BASE_URL })
  try {
    const other = await context.newPage()
    await signIn(other, name)
    await expect(other.getByRole('link', { name: 'Users & access' })).toBeVisible()
    expect((await other.request.get('/api/v1/users')).status()).toBe(200)
    await page.getByRole('button', { name: `Manage permissions for ${name}` }).click()
    await editor.getByRole('checkbox', { name: /^users.manage/ }).uncheck()
    await editor.getByRole('button', { name: 'Save permissions' }).click()
    await expect(editor).not.toBeVisible()
    expect((await other.request.get('/api/v1/users')).status()).toBe(403)
    await other.goto('/users')
    await expect(other.getByRole('heading', { name: 'Access restricted' })).toBeVisible()
  } finally { await context.close() }
})

test('login fits a mobile screen', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 })
  await page.goto('/login')
  await expect(page.getByRole('button', { name: 'Sign in', exact: true })).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await page.screenshot({ path: '/tmp/pwint-auth-login.png', fullPage: true })
})
