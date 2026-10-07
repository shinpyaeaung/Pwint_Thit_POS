import { test, expect } from '@playwright/test'
import { signIn } from './session'
test('warehouse prices use finalized landed cost and save linked bottle/carton prices',async({page})=>{
 test.setTimeout(90000)
 page.setDefaultTimeout(10000)
 await signIn(page,'browser-packaging-owner')
 const suffix=crypto.randomUUID().slice(0,8),headers={Origin:process.env.E2E_BASE_URL!,'X-Pwint-Thit-Request':'1'}
 const create=async(path:string,data:unknown,status=201)=>{const r=await page.request.post(`/api/v1${path}`,{headers,data});expect(r.status(),await r.text()).toBe(status);return status===204?null:r.json()}
 const product=await create('/products',{name:`Landed bottles ${suffix}`,base_unit_code:'BOTTLE',is_active:true,packaging:[{unit_code:'BOTTLE',units_per_pack:'1',is_default_sale:true,is_default_purchase:false},{unit_code:'CARTON',units_per_pack:'12',is_default_purchase:true,is_default_sale:false}]})
 const supplier=await create('/suppliers',{name:`Landed supplier ${suffix}`,is_active:true})
 const warehouse={...await create('/warehouses',{name:`Home ${suffix}`,code:`HOME-${suffix}`}),name:`Home ${suffix}`}
 const other={...await create('/warehouses',{name:`Branch ${suffix}`,code:`BR-${suffix}`}),name:`Branch ${suffix}`}
 const purchase=await create('/purchases',{request_id:crypto.randomUUID(),supplier_id:supplier.id,purchased_at:'2026-01-15T00:00:00Z',currency_code:'MMK',mmk_per_unit:'1',items:[{product_id:product.id,unit_code:'CARTON',quantity:'2',units_per_pack:'12',unit_price_original:'220000'}]})
 for(const [w,cargo] of [[warehouse,'20000'],[other,'32000']] as const){
  const shipment=await create('/shipments',{request_id:crypto.randomUUID(),start_location:'Supplier',destination_warehouse_id:w.id,items:[{purchase_item_id:purchase.items[0].id,expected_quantity:'12'}]})
  await create(`/shipments/${shipment.id}/stages`,{request_id:crypto.randomUUID(),version:shipment.version,start_location:'Supplier',destination:w.name,provider_name:'Cargo terminal',transportation_fee_mmk:cargo,loading_fee_mmk:'0',unloading_fee_mmk:'0',other_fee_mmk:'0'},204)
  for(const status of ['IN_TRANSIT','ARRIVED']){
   const current=await(await page.request.get(`/api/v1/shipments/${shipment.id}`)).json()
   const r=await page.request.put(`/api/v1/shipments/${shipment.id}/status`,{headers,data:{version:current.version,status,shipped_at:"2026-01-16T00:00:00Z",arrived_at:status==='ARRIVED'?"2026-01-17T00:00:00Z":""}});expect(r.status(),await r.text()).toBe(204)
  }
  const path=`/shipments/${shipment.id}/landed-cost`
  const {source}=await(await page.request.get(`/api/v1${path}`)).json()
  const input={version:source.version,method:'QUANTITY',notes:'Confirmed all 12 bottles',items:[{id:source.items[0].id,sellable_quantity:'12'}]}
  const preview=await create(`${path}/preview`,input,200)
  await create(`${path}/finalize`,{...input,preview_token:preview.preview_token},201)
 }
 await page.goto('/warehouse-prices')
 const chooseWarehouse=async(name:string)=>{await page.getByRole('combobox',{name:'Pricing warehouse',exact:true}).click();await page.getByRole('option',{name,exact:true}).click()}
 await chooseWarehouse(warehouse.name)
 await page.getByRole('searchbox',{name:'Find pricing product'}).fill(suffix)
 await page.getByRole('button',{name:'Set prices',exact:true}).click()
 const table=page.getByRole('table',{name:'Landed cost breakdown'})
 await expect(table.getByRole('row').filter({hasText:'Purchase cost'})).toContainText('220,000')
 await expect(table.getByRole('row').filter({hasText:'Cargo fees'})).toContainText('20,000')
 await expect(table.getByRole('row').filter({hasText:'Landed cost'})).toContainText('240,000')
 await expect(table.getByRole('row').filter({hasText:'Landed cost'})).toContainText('20,000')
 await page.getByLabel('Retail price per BOTTLE',{exact:true}).fill('21000')
 await page.getByLabel('Wholesale price per BOTTLE',{exact:true}).fill('20500')
 await expect(page.getByLabel('Calculated selling prices')).toContainText('252,000 MMK / CARTON')
 await page.setViewportSize({width:375,height:812})
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
 await page.getByRole('dialog').screenshot({path:'/tmp/pwint-landed-pricing-mobile.png'})
 await page.getByRole('button',{name:'Save prices',exact:true}).click()
 await expect(page.getByRole('dialog')).toHaveCount(0)
 await page.reload()
 await chooseWarehouse(warehouse.name)
 await page.getByRole('searchbox',{name:'Find pricing product'}).fill(suffix)
 await expect(page.getByRole('table',{name:'Warehouse selling prices'})).toContainText('CARTON: 252,000 / 246,000')
 await page.getByRole('button',{name:'Set prices',exact:true}).click()
 await page.getByRole('combobox',{name:'Set selling prices by',exact:true}).click()
 await page.getByRole('option',{name:'Percentage markup on landed cost',exact:true}).click()
 await page.getByLabel('Retail markup (%)',{exact:true}).fill('5')
 await page.getByLabel('Wholesale markup (%)',{exact:true}).fill('2.5')
 await expect(page.getByLabel('Calculated selling prices')).toContainText('21,000 MMK / BOTTLE · 252,000 MMK / CARTON')
 await page.getByRole('button',{name:'Save prices',exact:true}).click()
 await expect(page.getByRole('dialog')).toHaveCount(0)
 await chooseWarehouse(other.name)
 await page.getByRole('button',{name:'Set prices',exact:true}).click()
 await expect(table.getByRole('row').filter({hasText:'Landed cost'})).toContainText('252,000')
 await page.getByLabel('Retail price per BOTTLE',{exact:true}).fill('23000')
 await page.getByLabel('Wholesale price per BOTTLE',{exact:true}).fill('22000')
 await page.getByRole('button',{name:'Save prices',exact:true}).click()
 await expect(page.getByRole('dialog')).toHaveCount(0)
 await expect(page.getByRole('table',{name:'Warehouse selling prices'})).toContainText('CARTON: 276,000 / 264,000')
 await chooseWarehouse(warehouse.name)
 await expect(page.getByRole('table',{name:'Warehouse selling prices'})).toContainText('CARTON: 252,000 / 246,000')
})
