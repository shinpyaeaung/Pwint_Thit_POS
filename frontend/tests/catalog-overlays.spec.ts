import { test, expect } from '@playwright/test'
import { signIn } from './session'

test('catalog dialogs display complete compact forms in Safari and Chrome', async ({ page }) => {
  await signIn(page, 'browser-shipping-owner')
  await page.goto('/catalog')
  const suffix=String(Date.now())
  for (const [tab,kind] of [['Categories','category'],['Brands','brand'],['Units','unit']]) {
    await page.getByRole('button',{name:tab,exact:true}).click()
    await page.getByRole('button',{name:`Add ${kind}`,exact:true}).click()
    const dialog=page.getByRole('dialog',{name:`Add ${kind}`,exact:true})
    for (const viewport of [{width:1280,height:800},{width:1024,height:600},{width:800,height:450}]) {
      await page.setViewportSize(viewport)
      await expect.poll(async()=>{
        const b=await dialog.boundingBox()
        return !!b && b.width<=512 && b.height<=viewport.height-31 && b.x>=15 && b.y>=15 && Math.abs(b.x+b.width/2-viewport.width/2)<1 && Math.abs(b.y+b.height/2-viewport.height/2)<1
      }).toBe(true)
      await expect(dialog.getByLabel('Name',{exact:true})).toBeInViewport()
      if(kind==='unit') await expect(dialog.getByLabel('Unit code',{exact:true})).toBeInViewport()
      for (const name of ['Close','Cancel','Save']) await expect(dialog.getByRole('button',{name,exact:true})).toBeInViewport()
    }
    await dialog.getByLabel('Name',{exact:true}).fill(`Overlay ${kind} ${suffix}`)
    if(kind==='unit') await dialog.getByLabel('Unit code',{exact:true}).fill(`WK${suffix}`)
    await page.screenshot({path:`/tmp/pwint-${test.info().project.name}-${kind}.png`})
    await dialog.getByRole('button',{name:'Save',exact:true}).click()
    await expect(dialog).toHaveCount(0)
  }
  await page.goto('/design-system')
  for(const [button,title] of [['Preview modal','Shipment note preview'],['Preview drawer','Shipment detail preview'],['Preview confirmation','Confirm preview action?']]) {
    await page.getByRole('button',{name:button,exact:true}).click()
    const dialog=page.getByRole('dialog',{name:title,exact:true})
    await expect(dialog.getByRole('button',{name:'Close',exact:true})).toBeInViewport()
    await dialog.getByRole('button',{name:'Close',exact:true}).click()
    await expect(dialog).toHaveCount(0)
  }
})
