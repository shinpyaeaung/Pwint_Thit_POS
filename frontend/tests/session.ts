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
  // The shell renders before its lazy destination. Wait for the destination and
  // initial dashboard query before tests navigate away (WebKit reports canceled loads).
  await expect(page.locator('main h1')).toBeVisible()
  await expect(page.getByText('Loading business snapshot…', { exact: true })).toHaveCount(0)
}

// Legacy workflow tests explicitly select the funded account seeded in their disposable database.
export function paymentBody(path:string,data:unknown){
 const eligible=path==='/pos/quote'||path==='/pos/checkout'||path==='/transport-payments'||path==='/expenses'||/^\/returns\/(sales|purchases)(\/preview)?$/.test(path)||/^\/(customers|purchases)\/[^/]+\/payments$/.test(path)
 return eligible&&data&&typeof data==='object'&&!('account_id' in data)&&!('creditor_id' in data)?{...data,account_id:('method' in data?data.method:'method_code' in data?data.method_code:'payment_method' in data?data.payment_method:'CASH')==='CASH'?'00000000-0000-0000-0000-000000000999':'00000000-0000-0000-0000-000000000998'}:data
}

export async function expectChartsFit(page: Page) {
  await expect.poll(()=>page.locator('[data-testid="money-chart"] svg.recharts-surface').evaluateAll(elements=>elements.length>0&&elements.every(element=>{
    const svg=element as SVGSVGElement
    return Math.abs(svg.viewBox.baseVal.width-svg.getBoundingClientRect().width)<2
  }))).toBe(true)
}
