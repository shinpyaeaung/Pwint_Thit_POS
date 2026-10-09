import {test,expect} from '@playwright/test'
import {signIn} from './session'
test('warehouse filters and optional stock/brand groups preserve variant quantities and prices',async({page})=>{
 test.setTimeout(120000)
 await signIn(page,'browser-packaging-owner')
 const suffix=crypto.randomUUID().slice(0,8),headers={Origin:process.env.E2E_BASE_URL!,'X-Pwint-Thit-Request':'1'}
 const post=async(path:string,data:unknown,status=201)=>{const r=await page.request.post(`/api/v1${path}`,{headers,data});expect(r.status(),await r.text()).toBe(status);return r.json()}
 const get=async(path:string)=>{const r=await page.request.get(`/api/v1${path}`);expect(r.status()).toBe(200);return r.json()}
 const brand=await post('/catalog/brands',{name:`Variants ${suffix}`,is_active:true})
 const variants=[]
 for(const [flavor,price] of [['Chocolate','150'],['Milk','180']])variants.push(await post('/products',{name:`${flavor} ${suffix}`,brand_id:brand.id,base_unit_code:'PIECE',is_active:true,packaging:[{unit_code:'PIECE',units_per_pack:'1',is_default_purchase:true,is_default_sale:true,retail_price_mmk:price,wholesale_price_mmk:price},{unit_code:'CARTON',units_per_pack:'12'}]}))
 const supplier=await post('/suppliers',{name:`Group supplier ${suffix}`,is_active:true})
 const warehouse=await post('/warehouses',{name:`Stocked ${suffix}`,code:`ST-${suffix}`}),empty=await post('/warehouses',{name:`Empty ${suffix}`,code:`EM-${suffix}`})
 const purchase=await post('/purchases',{request_id:crypto.randomUUID(),supplier_id:supplier.id,purchased_at:'2026-01-15T00:00:00Z',currency_code:'MMK',mmk_per_unit:'1',items:variants.map((p,i)=>({product_id:p.id,unit_code:'PIECE',units_per_pack:'1',quantity:i?'24':'48',unit_price_original:'100'}))})
 for(let n=0;n<3;n++){
  const shipment=await post('/shipments',{request_id:crypto.randomUUID(),start_location:'Supplier',destination_warehouse_id:warehouse.id,items:[{purchase_item_id:purchase.items[n===2?1:0].id,expected_quantity:'24'}]})
  for(const status of ['IN_TRANSIT','ARRIVED']){const current=await get(`/shipments/${shipment.id}`);const r=await page.request.put(`/api/v1/shipments/${shipment.id}/status`,{headers,data:{version:current.version,status,shipped_at:'2026-01-16T00:00:00Z',arrived_at:'2026-01-17T00:00:00Z'}});expect(r.status(),await r.text()).toBe(204)}
  const receipt=await get(`/receiving/shipments/${shipment.id}`)
  const body={finalize_costs:true,request_id:crypto.randomUUID(),shipment_id:shipment.id,version:receipt.version,received_at:'2026-01-18T00:00:00Z',items:[{shipment_item_id:receipt.items[0].id,carton_size:'12',received_cartons:'2',received_units:'0',damaged_quantity:'0',batch_number:`GROUP-${n}-${suffix}`,notes:''}]}
  const preview=await post('/receiving/preview',body,200);await post('/receiving',{...body,preview_token:preview.preview_token})
 }
 const choose=async(label:string,name:string)=>{await page.getByRole('combobox',{name:label,exact:true}).click();await page.getByRole('option',{name,exact:true}).click()}
 await page.goto(`/inventory?q=${suffix}`)
 await choose('Inventory warehouse',`Stocked ${suffix}`)
 await expect(page.getByRole('table')).toContainText(`GROUP-0-${suffix}`)
 await choose('Stock grouping','Combine matching product stock')
 await expect(page.getByRole('table')).toContainText('Available 48 PIECE · 4 cartons + 0 pieces')
 await page.getByText(`Chocolate ${suffix}`,{exact:true}).click()
 await expect(page.getByRole('table')).toContainText(`GROUP-1-${suffix}`)
 await expect(page.getByRole('table')).toContainText('Landed Cost per Carton: 1,200 MMK')
 await choose('Stock grouping','Group variants by brand')
 await expect(page.getByRole('table')).toContainText(`Variants ${suffix}`)
 await expect(page.getByRole('table')).toContainText(`Chocolate ${suffix}`)
 await expect(page.getByRole('table')).toContainText(`Milk ${suffix}`)
 await choose('Inventory warehouse',`Empty ${suffix}`)
 await expect(page.getByRole('heading',{name:'No records yet',exact:true})).toBeVisible()
 await expect(page.getByText(`Chocolate ${suffix}`,{exact:true})).toHaveCount(0)
 await page.goto(`/warehouse-prices?warehouse_id=${warehouse.id}&q=${suffix}`)
 await expect(page.getByRole('table')).toContainText('PIECE: 150 / 150')
 await expect(page.getByRole('table')).toContainText('PIECE: 180 / 180')
 await choose('Pricing warehouse',`Empty ${suffix}`)
 await expect(page.getByRole('heading',{name:'No records yet',exact:true})).toBeVisible()
 await choose('Pricing warehouse',`Stocked ${suffix}`)
 await expect(page.getByRole('button',{name:'Set prices',exact:true})).toHaveCount(2)
 await page.goto('/pos')
 await choose('POS warehouse',`Stocked ${suffix}`)
 await page.getByLabel('Scan barcode or search products',{exact:true}).fill(suffix)
 await expect(page.getByRole('button',{name:`Add ${variants[0].sku}`,exact:true})).toBeVisible()
 await choose('POS warehouse',`Empty ${suffix}`)
 await expect(page.getByText('No matching stock at this warehouse.',{exact:true})).toBeVisible()
 await expect(page.getByRole('button',{name:`Add ${variants[0].sku}`,exact:true})).toHaveCount(0)
 await page.goto('/products')
 await page.getByRole('searchbox',{name:'Search products'}).fill(suffix)
 await page.getByLabel('Group variants by brand',{exact:true}).check()
 await expect(page.getByRole('table')).toContainText(`Variants ${suffix}`)
 await expect(page.getByRole('table')).toContainText(variants[0].sku)
 await expect(page.getByRole('table')).toContainText(variants[1].sku)
 await page.screenshot({path:'/tmp/pwint-product-variant-groups.png',fullPage:true})
 expect((await get(`/inventory?warehouse_id=${empty.id}`)).total).toBe(0)
})
