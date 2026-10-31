import { test, expect } from '@playwright/test'
import { signIn } from './session'

test('upload, persist, replace and remove product photos with responsive official branding', async ({ page }) => {
  await signIn(page, 'browser-images-owner')
  const name = `Image product ${Date.now()}`
  const image = async (color: string, width = 24, height = 24) => Buffer.from(await page.evaluate(({ color, width, height }) => {
    const canvas = document.createElement('canvas'); canvas.width = width; canvas.height = height
    const ctx = canvas.getContext('2d')!; ctx.fillStyle = color; ctx.fillRect(0, 0, width, height)
    if (color === 'noise') {
      const pixels = ctx.createImageData(width, height)
      let seed = 12345
      for (let i = 0; i < pixels.data.length; i++) {
        seed = (Math.imul(seed, 1664525) + 1013904223) | 0
        pixels.data[i] = i % 4 === 3 ? 128 : seed >>> 24
      }
      ctx.putImageData(pixels, 0, 0)
    }
    return canvas.toDataURL('image/png').split(',')[1]
  }, { color, width, height }), 'base64')
  // A valid high-resolution photo with >2 MiB input exercises both old rejection paths.
  const first = Buffer.concat([await image('red', 5000, 3000), Buffer.alloc(3 * 1024 * 1024)]), second = await image('noise', 1600, 1200)
  expect(second.length).toBeGreaterThan(2 * 1024 * 1024)
  await page.goto('/products/new')
  await page.getByLabel('Product name', { exact: true }).fill(name)
  await page.getByLabel('Upload product image').setInputFiles({ name: 'photo.png', mimeType: 'image/png', buffer: first })
  await expect(page.getByRole('img', { name: 'Product preview', exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'Create product', exact: true }).click()
  await expect(page).toHaveURL(/\/products\/[a-f0-9-]{36}$/)
  const path = new URL(page.url()).pathname
  const photo = page.getByRole('img', { name, exact: true })
  await expect(photo).toBeVisible()
  await expect.poll(() => photo.evaluate((img: HTMLImageElement) => img.naturalWidth)).toBe(2048)
  expect((await page.request.get(`/api/v1${path}/image`)).headers()['content-type']).toContain('image/png')
  expect((await (await page.request.get(`/api/v1${path}/image`)).body()).length).toBeLessThan(2 * 1024 * 1024)
  const firstVersion = (await (await page.request.get(`/api/v1${path}`)).json()).image_version
  await page.reload()
  await expect(photo).toBeVisible()
  await page.getByRole('link', { name: 'Edit Product', exact: true }).click()
  await page.getByRole('button', { name: 'Save changes', exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`${path}$`))
  expect((await (await page.request.get(`/api/v1${path}`)).json()).image_version).toBe(firstVersion)
  await page.getByRole('link', { name: 'Edit Product', exact: true }).click()
  await page.getByLabel('Upload product image').setInputFiles({ name: 'replacement.png', mimeType: 'image/png', buffer: second })
  await page.getByRole('button', { name: 'Save changes', exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`${path}$`))
  expect((await (await page.request.get(`/api/v1${path}`)).json()).image_version).not.toBe(firstVersion)
  await expect.poll(() => photo.evaluate((img: HTMLImageElement) => img.naturalWidth)).toBeLessThan(1600)
  expect((await (await page.request.get(`/api/v1${path}/image`)).body()).length).toBeLessThan(2 * 1024 * 1024)
  await page.goto('/products')
  await page.getByRole('searchbox', { name: 'Search products' }).fill(name)
  await expect(page.getByRole('img', { name, exact: true })).toBeVisible()
  const logo = page.getByRole('img', { name: 'Pwint Thit Distribution', exact: true })
  await expect(logo).toBeVisible()
  expect((await logo.boundingBox())!.width).toBeLessThanOrEqual(128)
  await expect.poll(() => logo.evaluate((img: HTMLImageElement) => img.naturalWidth)).toBeGreaterThan(0)
  await page.screenshot({ path: `/tmp/pwint-images-desktop-${test.info().project.name}.png` })
  await page.setViewportSize({ width: 375, height: 667 })
  await page.getByRole('button', { name: 'Open navigation' }).click()
  await expect(logo).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await page.screenshot({ path: `/tmp/pwint-images-mobile-${test.info().project.name}.png` })
  await page.goto(`${path}/edit`)
  await page.getByRole('button', { name: 'Remove image', exact: true }).click()
  await page.getByRole('button', { name: 'Save changes', exact: true }).click()
  await expect(page).toHaveURL(new RegExp(`${path}$`))
  expect((await page.request.get(`/api/v1${path}/image`)).status()).toBe(404)
  await expect(page.getByRole('img', { name, exact: true })).toHaveCount(0)
})
