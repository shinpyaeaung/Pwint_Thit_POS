import { test, expect, type Page } from '@playwright/test'
import { signIn, staff } from './session'

test('shared table, exact decimal fields and accessible overlays work together', async ({ page }) => {
  await signIn(page)
  await page.goto('/design-system')
  await expect(page.getByRole('heading', { name: 'Pwint Thit UI library' })).toBeVisible()
  const table = page.getByRole('region', { name: 'Sample distribution records table' })
  await expect(table.getByText('Packaged tea')).not.toBeVisible()
  await page.getByRole('button', { name: 'Next', exact: true }).click()
  await expect(table.getByText('Packaged tea')).toBeVisible()
  await page.getByRole('button', { name: 'Product', exact: true }).click()
  await page.getByRole('button', { name: 'Product', exact: true }).click()
  await expect(table.getByRole('columnheader', { name: 'Product' })).toHaveAttribute('aria-sort', 'descending')
  await expect(table.getByRole('row').nth(1)).toContainText('Packaged tea')
  await page.getByRole('searchbox', { name: 'Search sample records' }).fill('nothing matches')
  await expect(page.getByRole('heading', { name: 'No records yet' })).toBeVisible()
  await page.getByRole('button', { name: 'Reset filters' }).click()
  const amount = page.getByLabel('Purchase amount (MMK)', { exact: false })
  await amount.fill('9999999999999999.1234')
  await page.getByRole('button', { name: 'Validate preview' }).click()
  await expect(page.getByText('Valid preview: 9999999999999999.1234 MMK · 12 bottles', { exact: true })).toBeVisible()
  for (const invalid of ['1e5', '12.12345']) {
    await amount.fill(invalid)
    expect(await amount.evaluate((el: HTMLInputElement) => el.checkValidity())).toBe(false)
    await expect(amount).toHaveAttribute('aria-invalid', 'true')
  }
  await amount.fill('250000.0000')
  const quantity = page.getByLabel('Received quantity (bottles)', { exact: false })
  await quantity.fill('0.123456')
  await page.getByRole('button', { name: 'Validate preview' }).click()
  await expect(page.getByText('Valid preview: 250000.0000 MMK · 0.123456 bottles', { exact: true })).toBeVisible()
  await quantity.fill('-1')
  expect(await quantity.evaluate((el: HTMLInputElement) => el.checkValidity())).toBe(false)
  await quantity.fill('12')
  const trigger = page.getByRole('button', { name: 'Preview modal', exact: true })
  await trigger.click()
  const modal = page.getByRole('dialog', { name: 'Shipment note preview' })
  await expect(modal).toBeVisible()
  for (const viewport of [{ width: 1280, height: 900 }, { width: 375, height: 812 }, { width: 667, height: 375 }]) {
    await page.setViewportSize(viewport)
    await expect.poll(async () => {
      const box = await modal.boundingBox()
      return !!box && box.x >= 15 && box.y >= 15 && box.width <= 512 && box.height <= viewport.height - 31 && Math.abs(box.x + box.width / 2 - viewport.width / 2) < 1 && Math.abs(box.y + box.height / 2 - viewport.height / 2) < 1
    }).toBe(true)
    await expect(modal.getByRole('button', { name: 'Close', exact: true })).toBeInViewport()
    await expect(modal.getByRole('button', { name: 'Done', exact: true })).toBeInViewport()
    await modal.getByLabel('Note', { exact: true }).fill('Sample note')
  }
  await page.setViewportSize({ width: 1280, height: 900 })
  await modal.screenshot({ path: '/tmp/pwint-modal-normal-preview.png' })

  for (let i = 0; i < 5; i++) await page.keyboard.press('Tab')
  expect(await modal.evaluate(el => el.contains(document.activeElement))).toBe(true)
  await page.keyboard.press('Escape')
  await expect(modal).not.toBeVisible()
  await expect(trigger).toBeFocused()
  await page.getByRole('button', { name: 'Preview drawer', exact: true }).click()
  await expect(page.getByRole('dialog', { name: 'Shipment detail preview' })).toBeVisible()
  await page.keyboard.press('Escape')
  await page.getByRole('button', { name: 'Preview confirmation', exact: true }).click()
  await page.getByRole('button', { name: 'Cancel', exact: true }).click()
  await expect(page.getByText('Preview confirmed. No records changed.')).not.toBeVisible()
  await page.getByRole('button', { name: 'Preview confirmation', exact: true }).click()
  await page.getByRole('button', { name: 'Confirm preview', exact: true }).click()
  await expect(page.getByText('Preview confirmed. No records changed.')).toBeVisible()
  await page.evaluate(() => window.scrollTo(0, 0))
  await page.screenshot({ path: '/tmp/pwint-phase4-library.png', fullPage: true })
  await checkPreviewBounds(page)
  await page.setViewportSize({ width: 1280, height: 900 })
  await page.goto('/')
  await expect(page.getByRole('status')).toContainText('All systems connected')
  await page.screenshot({ path: '/tmp/pwint-phase4-workspace.png', fullPage: true })
})

test('mobile navigation traps focus, returns focus and respects staff permissions', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 })
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await signIn(page, staff)
  const trigger = page.getByRole('button', { name: 'Open navigation' })
  await trigger.click()
  const menu = page.getByRole('dialog', { name: 'Navigation', exact: true })
  await expect(menu).toBeVisible()
  await expect(menu.getByRole('link', { name: 'Users & access' })).not.toBeVisible()
  await expect(menu.getByRole('link', { name: 'UI library' })).not.toBeVisible()
  await page.keyboard.press('Escape')
  await expect(trigger).toBeFocused()
  await page.goto('/design-system')
  await expect(page.getByRole('heading', { name: 'Access restricted' })).toBeVisible()
  await page.goto('/')
  await expect(page.getByRole('status')).toContainText('All systems connected')
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await page.screenshot({ path: '/tmp/pwint-phase4-mobile.png', fullPage: true })
})


async function checkPreviewBounds(page: Page) {
  await page.goto('/design-system')
  for (const viewport of [{width:1280,height:900},{width:1024,height:600},{width:667,height:375}]) {
    await page.setViewportSize(viewport)
    for (const [button,title,drawer] of [['Preview modal','Shipment note preview',false],['Preview drawer','Shipment detail preview',true],['Preview confirmation','Confirm preview action?',false]] as const) {
      await page.getByRole('button',{name:button,exact:true}).click()
      const dialog=page.getByRole('dialog',{name:title,exact:true})
      await expect(dialog).toBeVisible()
      await expect.poll(async()=>{
        const b=await dialog.boundingBox()
        return !!b && b.x>=0 && b.y>=0 && b.x+b.width<=viewport.width+1 && b.y+b.height<=viewport.height+1 && b.width<=512 && (drawer || b.height<500)
      }).toBe(true)
      await expect(dialog.getByRole('button',{name:'Close',exact:true})).toBeInViewport()
      if(button==='Preview modal') {
        const note=dialog.getByLabel('Note',{exact:true})
        await note.evaluate(el=>{el.style.height='1000px'})
        await expect(dialog.getByRole('button',{name:'Done',exact:true})).toBeInViewport()
        expect(await note.locator('..').locator('..').evaluate(el=>el.scrollHeight>el.clientHeight)).toBe(true)
      }
      if(button==='Preview confirmation') await expect(dialog.getByRole('button',{name:'Confirm preview',exact:true})).toBeInViewport()
      await dialog.screenshot({path:`/tmp/pwint-${button.replaceAll(' ','-')}-${viewport.width}.png`})
      await dialog.getByRole('button',{name:'Close',exact:true}).click()
      await expect(dialog).toHaveCount(0)
    }
  }
}
