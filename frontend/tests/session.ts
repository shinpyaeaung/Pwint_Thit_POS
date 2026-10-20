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

// Legacy workflow tests explicitly select the funded account seeded in their disposable database.
export function paymentBody(path:string,data:unknown){
 const eligible=path==='/pos/quote'||path==='/pos/checkout'||path==='/transport-payments'||path==='/expenses'||/^\/returns\/(sales|purchases)(\/preview)?$/.test(path)||/^\/(customers|purchases)\/[^/]+\/payments$/.test(path)
 return eligible&&data&&typeof data==='object'&&!('account_id' in data)&&!('creditor_id' in data)?{...data,account_id:'00000000-0000-0000-0000-000000000999'}:data
}
