import { ProductImage } from '@/components/shared/product-image'
import { AccountSelect } from '@/pages/finance/AccountSelect'
import { FulfillmentFields, type Fulfillment } from '@/components/shared/fulfillment'
import { useEffect,useRef,useState,useCallback } from 'react'
import { useMutation,useQuery,useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { Select,SelectItem } from '@/components/ui/select'
import { PageHeader,FormField,CurrencyInput,QuantityInput,Modal,LoadingState } from '@/components/shared'
import { requestJSON,ApiError } from '@/services/api'
import { can,permissions,type CurrentUser } from '@/permissions'
import { amount } from '../purchases/types'
import { Field } from '../shipments/Fields'
import { useCart,lineTotal,cartTotal,price,type Product,type Mode } from './cart'
import { PriceEditor,CustomerEditor } from './Editors'
type Quote={requires_below_cost_approval:boolean;can_approve_below_cost:boolean;quote_hash:string;total_mmk:string;paid_mmk:string;change_mmk:string;outstanding_mmk:string;cost_mmk?:string;profit_mmk?:string;lines:{product_name:string;quantity:string;unit_code:string;total_mmk:string;cost_mmk?:string;below_cost:boolean}[]}
export default function POS({current}:{current:CurrentUser}){
 const [fulfillment,setFulfillment]=useState<Fulfillment>({mode:'COLLECTION'})
 const client=useQueryClient(),cart=useCart(),searchRef=useRef<HTMLInputElement>(null),customerRef=useRef<HTMLInputElement>(null)
 const [warehouse,setWarehouse]=useState(''),[mode,setMode]=useState<Mode>('RETAIL'),[search,setSearch]=useState(''),[debounced,setDebounced]=useState(''),[message,setMessage]=useState(''),[editor,setEditor]=useState<Product|null>(null),[addCustomer,setAddCustomer]=useState(false)
 const [customer,setCustomer]=useState(''),[customerSearch,setCustomerSearch]=useState(''),[tender,setTender]=useState(''),[method,setMethod]=useState('CASH'),[reference,setReference]=useState(''),[due,setDue]=useState(''),[reason,setReason]=useState(''),[requestID,setRequestID]=useState(()=>crypto.randomUUID())
 const [account,setAccount]=useState('');
 const [sellOnCredit,setSellOnCredit]=useState(false)
 const [approved,setApproved]=useState(false)
 const [selectedCustomerLabel,setSelectedCustomerLabel]=useState('')
 const [review,setReview]=useState<{quote:Quote;payload:object}|null>(null)
 useEffect(()=>{useCart.getState().clear()},[current.id])
 useEffect(()=>{const timer=setTimeout(()=>setDebounced(search),120);return()=>clearTimeout(timer)},[search])
 const warehouses=useQuery({queryKey:['pos-warehouses'],queryFn:()=>requestJSON<{id:string;name:string}[]>('/pos/warehouses')})
 const activeWarehouse=warehouse||warehouses.data?.[0]?.id||''
 const scanGeneration=useRef(0)
 const products=useQuery({queryKey:['pos-products',activeWarehouse,debounced],queryFn:({signal})=>requestJSON<Product[]>(`/pos/products?warehouse_id=${activeWarehouse}&q=${encodeURIComponent(debounced)}`,{signal}),enabled:!!activeWarehouse,staleTime:15000})
 const customers=useQuery({queryKey:['pos-customers',customerSearch],queryFn:({signal})=>requestJSON<{id:string;name:string;code:string;customer_type:string}[]>(`/pos/customers?q=${encodeURIComponent(customerSearch)}`,{signal})})
 const customerPrices=useQuery({queryKey:['pos-customer-prices',customer],queryFn:()=>requestJSON<{product_id:string;unit_code:string;price_mmk:string}[]>(`/customers/${customer}/prices`),enabled:!!customer})
 const effectiveLines=cart.lines.map(l=>({...l,product:{...l.product,packaging:l.product.packaging.map(p=>({...p,special_price_mmk:customer?customerPrices.data?.find(v=>v.product_id===l.product.id&&v.unit_code===p.unit_code)?.price_mmk:undefined}))}}))
 const totals=effectiveLines.map(l=>lineTotal(l,mode)),sum=cartTotal(totals),valid=sum!==null&&(!customer||customerPrices.isSuccess),total=valid?sum:'0.0000'
 const add=useCallback((p:Product,barcode='',clearSearch=true)=>{const u=p.packaging.find(u=>barcode&&u.barcode===barcode)||(barcode&&p.barcode===barcode?p.packaging.find(u=>u.unit_code===p.base_unit_code):undefined)||p.packaging.find(u=>u.is_default_sale)||p.packaging[0];if(!u){setMessage('Configure product packaging first.');return}if(price({...u,special_price_mmk:customer?customerPrices.data?.find(v=>v.product_id===p.id&&v.unit_code===u.unit_code)?.price_mmk:undefined},mode)===null){setMessage('Set a selling price for this unit first.');return}try{cart.add(p,u.unit_code);setMessage('');if(clearSearch)setSearch('');searchRef.current?.focus()}catch{setMessage('Correct the existing quantity first.')}},[cart,mode,customer,customerPrices.data])
 async function scan(){const generation=scanGeneration.current;const code=search.trim();if(!activeWarehouse||!code)return;setSearch('');try{const found=await client.fetchQuery({queryKey:['pos-products',activeWarehouse,code],queryFn:()=>requestJSON<Product[]>(`/pos/products?warehouse_id=${activeWarehouse}&q=${encodeURIComponent(code)}`),staleTime:0});if(generation!==scanGeneration.current)return;const exact=found.filter(p=>p.barcode===code||p.sku===code||p.packaging.some(u=>u.barcode===code));if(exact.length===1)add(exact[0],code,false);else if(found.length===1)add(found[0],code,false);else{setSearch(previous=>previous||code);setMessage(found.length?'Choose a product from the results.':'No matching product.')}}catch(e){if(generation!==scanGeneration.current)return;setSearch(previous=>previous||code);setMessage((e as Error).message)}}

 const quote=useMutation({mutationFn:async()=>{const payload={account_id:account||undefined,sell_on_credit:sellOnCredit,fulfillment,request_id:requestID,warehouse_id:activeWarehouse,customer_id:customer,pricing_mode:mode,payment_method:method,payment_reference:reference,tender_mmk:tender||(sellOnCredit?'0':total),due_date:sellOnCredit?due:'',reason,quote_hash:'',items:effectiveLines.map(l=>{const u=l.product.packaging.find(u=>u.unit_code===l.unit)!;return{product_id:l.product.id,unit_code:l.unit,units_per_pack:u.units_per_pack,quantity:l.quantity,unit_price_mmk:price(u,mode),discount_mmk:l.discount}})};const result=await requestJSON<Quote>('/pos/quote',{method:'POST',body:JSON.stringify(payload)});return{quote:result,payload:{...payload,quote_hash:result.quote_hash}}},onSuccess:r=>{setApproved(false);setReview(r)}})
 const checkout=useMutation({mutationFn:()=>requestJSON<{id:string}>('/pos/checkout',{method:'POST',body:JSON.stringify({...review!.payload,approve_below_cost:approved})}),onSuccess:r=>{cart.clear();window.location.assign(`/sales/${r.id}`)}})
 const uncertain=checkout.error instanceof ApiError&&(checkout.error.status===0||checkout.error.status>=500)
 useEffect(()=>{const keys=(e:KeyboardEvent)=>{if(e.key==='F2'){e.preventDefault();searchRef.current?.focus()}if(e.key==='F4'){e.preventDefault();customerRef.current?.focus()}if(e.key==='F8'&&!review&&!editor&&!addCustomer&&valid&&!quote.isPending){e.preventDefault();quote.mutate()}};window.addEventListener('keydown',keys);return()=>window.removeEventListener('keydown',keys)},[review,editor,addCustomer,valid,quote])
  return <>
    <PageHeader eyebrow="Sales / Counter" title="Point of sale" description="F2 search · Enter scan/add · F4 customer · F8 review checkout" actions={can(current, permissions.salesView) && <Button asChild variant="outline"><a href="/sales">Invoices</a></Button>} />
    
    {/* Warehouse and Mode Control Strip */}
    <div className="mb-6 grid gap-4 rounded-lg border border-border bg-surface p-4  sm:grid-cols-2">
      <FormField label="Warehouse" hint={cart.lines.length ? "Clear the cart before changing warehouse; cart stock belongs to this location." : "Stock availability is checked at this warehouse."}>
        {f => <Select {...f} aria-label="POS warehouse" value={activeWarehouse} disabled={cart.lines.length > 0 || !warehouses.data?.length} onValueChange={v => { scanGeneration.current++; setWarehouse(v); setEditor(null); setReview(null); setMessage(''); setSearch(''); setDebounced('') }}>
          {!activeWarehouse && <SelectItem value="" disabled>{warehouses.isPending ? "Loading warehouses…" : "No warehouse available"}</SelectItem>}
          {warehouses.data?.map(w => <SelectItem key={w.id} value={w.id}>{w.name}</SelectItem>)}
        </Select>}
      </FormField>
      <FormField label="Pricing mode">
        {f => <Select {...f} aria-label="Pricing mode" value={mode} onValueChange={v => setMode(v as Mode)}>
          <SelectItem value="RETAIL">Retail prices</SelectItem>
          <SelectItem value="WHOLESALE">Wholesale prices</SelectItem>
        </Select>}
      </FormField>
    </div>
    
    {warehouses.error && <p role="alert" className="mb-4 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">{warehouses.error.message}</p>}
    {warehouses.isSuccess && !warehouses.data.length && (
      <div role="status" className="mb-6 rounded-lg border border-amber-200 bg-amber-50/80 p-5 text-sm text-amber-950">
        <h2 className="font-semibold">Set up a warehouse before selling</h2>
        <p className="mt-1 leading-relaxed">No active warehouse is available. Create a warehouse from the Create shipment page using Add warehouse, then receive costed goods into it. POS can only sell received stock.</p>
        {can(current, permissions.shipmentsManage) && can(current, permissions.settingsManage) ? (
          <a href="/shipments/new" className="mt-3 inline-block font-semibold text-primary hover:underline">Open warehouse setup →</a>
        ) : (
          <p className="mt-2 text-muted-foreground">Ask your Super Admin to set up the warehouse and receive stock.</p>
        )}
      </div>
    )}

    <div className="grid items-start gap-6 xl:grid-cols-[1fr_1.15fr]">
      {/* Product Search & Catalog Panel */}
      <section className="panel min-w-0 p-5">
        <div className="mb-3 flex items-center justify-between">
          <label htmlFor="pos-search" className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Scan barcode or search products</label>
          <span className="hidden rounded-md bg-muted px-2 py-0.5 font-mono text-xs font-semibold text-muted-foreground sm:inline">F2</span>
        </div>
        <div className="relative">
          <input ref={searchRef} id="pos-search" className="field" autoFocus autoComplete="off" value={search} onChange={e => setSearch(e.target.value)} onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); void scan() } }} placeholder="Barcode, SKU or product name…" />
        </div>
        {message && <p role="alert" className="mt-2.5 rounded-lg bg-red-50 px-3 py-2 text-xs font-medium text-destructive">{message}</p>}
        {products.isPending && activeWarehouse ? (
          <LoadingState label="Loading products…" />
        ) : products.error ? (
          <p role="alert" className="mt-3 text-sm text-destructive">{products.error.message}</p>
        ) : (
          <div className="mt-4 max-h-[34rem] divide-y divide-border overflow-y-auto pr-1">
            {products.data?.map(p => (
              <div key={p.id} className="group flex items-center justify-between gap-3 py-3.5 transition-colors hover:bg-background/70">
                <button className="min-w-0 flex-1 text-left" onClick={() => add(p)}>
                  <span className="flex items-center gap-3"><ProductImage product={p}/><span className="block text-sm font-semibold text-foreground group-hover:text-primary transition-colors">{p.name}</span></span>
                  <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                    <span className="font-mono text-xs">{p.sku}</span>
                    <span>·</span>
                    <span className="inline-flex items-center rounded-md bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground">{amount(p.available_quantity)} {p.base_unit_code} available</span>
                  </div>
                </button>
                <div className="flex items-center gap-1.5 shrink-0">
                  {can(current, permissions.productsUpdate) && <Button size="sm" variant="ghost" onClick={() => setEditor(p)} aria-label={`Prices ${p.sku}`}>Prices</Button>}
                  <Button size="sm" variant="outline" onClick={() => add(p)} aria-label={`Add ${p.sku}`} className="gap-1">Add</Button>
                </div>
              </div>
            ))}
            {products.data?.length === 0 && <p className="py-12 text-center text-sm text-muted-foreground">No matching stock at this warehouse.</p>}
          </div>
        )}
      </section>

      {/* Cart & Checkout Panel */}
      <section className="panel min-w-0 p-5">
        <div className="mb-4 flex items-center justify-between border-b border-border pb-3">
          <div className="flex items-center gap-2">
            <h2 className="text-sm font-semibold tracking-tight text-foreground">Current sale</h2>
            <span className="rounded-full bg-muted px-2.5 py-0.5 text-xs font-semibold tabular-nums text-muted-foreground">{cart.lines.length} lines</span>
          </div>
          <Button variant="ghost" size="sm" onClick={() => { cart.clear(); setTender(''); setSellOnCredit(false); setDue(''); setRequestID(crypto.randomUUID()) }}>Clear cart</Button>
        </div>

        {/* Cart Item Cards */}
        <div className="space-y-3 max-h-[22rem] overflow-y-auto pr-1">
          {effectiveLines.map((l, i) => (
            <div key={l.id} className="rounded-lg border border-border/90 bg-muted p-3.5 transition-colors hover:bg-background/80">
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-2"><ProductImage product={l.product} className="size-9"/><p className="text-sm font-semibold text-foreground">{l.product.name}</p></div>
                <button className="text-xs font-semibold text-destructive hover:underline" aria-label={`Remove ${l.product.sku}`} onClick={() => cart.remove(l.id)}>Remove</button>
              </div>
              <div className="mt-3 grid grid-cols-2 gap-2.5 sm:grid-cols-4 sm:items-center">
                <div className="col-span-2 sm:col-span-1">
                  <Select aria-label={`Selling unit ${l.product.sku}`} value={l.unit} onValueChange={unit => cart.update(l.id, { unit })}>
                    {l.product.packaging.map(u => <SelectItem key={u.unit_code} value={u.unit_code} disabled={cart.lines.some(other => other.id !== l.id && other.product.id === l.product.id && other.unit === u.unit_code)}>{u.unit_code} · {price(u, mode) === null ? 'Price not set' : `${amount(price(u, mode)!)} MMK`}</SelectItem>)}
                  </Select>
                </div>
                <QuantityInput aria-label={`Quantity ${l.product.sku}`} value={l.quantity} onValueChange={quantity => cart.update(l.id, { quantity })} unit={l.unit} />
                {can(current, permissions.salesDiscount) && <CurrencyInput aria-label={`Discount ${l.product.sku}`} value={l.discount} onValueChange={discount => cart.update(l.id, { discount })} />}
                <p className="col-span-2 text-right text-sm font-semibold tabular-nums text-foreground sm:col-span-1">{totals[i] === null ? 'Check quantity / price' : `${amount(totals[i]!)} MMK`}</p>
              </div>
            </div>
          ))}
          {cart.lines.length === 0 && <p className="py-12 text-center text-sm text-muted-foreground">Scan a barcode or add a product to start.</p>}
        </div>

        {/* Prominent Total Bar */}
        <div className="my-5 flex items-baseline justify-between rounded-lg bg-muted/70 p-4 border border-border">
          <span className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Total Due</span>
          <span className="text-2xl font-semibold tabular-nums tracking-tight text-primary sm:text-3xl" data-testid="pos-total">{amount(total)} MMK</span>
        </div>

        {/* Customer & Checkout Form */}
        <div className="space-y-4">
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <label className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Customer & terms</label>
              <span className="hidden font-mono text-xs text-muted-foreground sm:inline">F4</span>
            </div>
            <input ref={customerRef} aria-label="Search customers" className="field" value={customerSearch} onChange={e => setCustomerSearch(e.target.value)} placeholder="Find customer by name, code or phone…" />
            <div className="flex items-center gap-2">
              <div className="min-w-0 flex-1">
                <Select aria-label="Sale customer" value={customer} onValueChange={v => { setCustomer(v); const c = customers.data?.find(c => c.id === v); if (c) { setMode(c.customer_type as Mode); setSelectedCustomerLabel(`${c.name} · ${c.code}`) } else if (!v) setSelectedCustomerLabel('') }}>
                  <SelectItem value="">Walk-in customer</SelectItem>
                  {customer && !customers.data?.some(c => c.id === customer) && <SelectItem value={customer}>{selectedCustomerLabel || 'Selected customer'}</SelectItem>}
                  {customers.data?.map(c => <SelectItem key={c.id} value={c.id}>{c.name} · {c.code}</SelectItem>)}
                </Select>
              </div>
              {can(current, permissions.customersManage) && <Button variant="outline" size="sm" onClick={() => setAddCustomer(true)} className="shrink-0">Add customer</Button>}
            </div>
          </div>

          {customer && <p className="text-xs font-medium text-emerald-700 bg-emerald-50 rounded-lg px-3 py-1.5">Customer special prices apply when configured.</p>}
          {customerPrices.error && <p role="alert" className="text-xs text-destructive">{customerPrices.error.message}</p>}
          {customers.error && <p role="alert" className="text-xs text-destructive">{customers.error.message}</p>}

          <div className="rounded-lg border border-border bg-background/50 p-3.5">
            <label className="flex items-center gap-2.5 text-sm font-semibold text-foreground cursor-pointer">
              <input type="checkbox" className="size-4 rounded accent-primary" checked={sellOnCredit} onChange={e => { setSellOnCredit(e.target.checked); setDue(''); quote.reset() }} />
              Sell on Credit
            </label>
            <p className="mt-1 text-xs leading-relaxed text-muted-foreground">{sellOnCredit ? 'Choose a customer and due date. Enter any payment received now; the remainder becomes customer debt.' : 'Full payment is required for this sale.'}</p>
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <AccountSelect value={account} onChange={setAccount} method={method} />
            <Select aria-label="Payment method" value={method} onValueChange={setMethod}>
              {[['CASH', 'Cash'], ['BANK_TRANSFER', 'Bank transfer'], ['MOBILE_PAYMENT', 'Mobile payment'], ['OTHER', 'Other']].map(([v, l]) => <SelectItem key={v} value={v}>{l}</SelectItem>)}
            </Select>
            <FormField label="Amount received (MMK)" hint={sellOnCredit ? "Leave blank if nothing is paid now." : "Leave blank for exact payment."}>
              {f => <CurrencyInput {...f} value={tender} onValueChange={setTender} placeholder={sellOnCredit ? '0' : total} />}
            </FormField>
            <Field label="Payment reference" value={reference} onChange={setReference} />
            {sellOnCredit && <Field label="Credit due date" type="date" value={due} onChange={setDue} />}
          </div>

          <FulfillmentFields value={fulfillment} onChange={setFulfillment} />
          <Field label="Discount / approval reason" value={reason} onChange={setReason} maxLength={2000} />

          {quote.error && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-destructive">{quote.error.message}</p>}

          <Button className="h-11 w-full text-sm font-semibold " disabled={!valid || quote.isPending || !can(current, permissions.paymentsManage)} onClick={() => quote.mutate()}>
            {quote.isPending ? 'Checking stock and totals…' : 'Review checkout · F8'}
          </Button>
          {!can(current, permissions.paymentsManage) && <p className="text-center text-xs text-muted-foreground">Payment permission is required to complete checkout.</p>}
        </div>
      </section>
    </div>
 {editor&&<PriceEditor warehouse={activeWarehouse} product={editor} onClose={()=>setEditor(null)}/>} {addCustomer&&<CustomerEditor onClose={()=>setAddCustomer(false)} onSaved={(id,name)=>{setSelectedCustomerLabel(name);setCustomerSearch(name);setCustomer(id)}}/>}
 {review&&<Modal open onOpenChange={v=>{if(!v&&!uncertain){setReview(null);checkout.reset()}}} title="Review checkout" description="Stock and prices are checked again when you complete the sale." busy={checkout.isPending||uncertain} animated={false} footer={<><Button variant="outline" disabled={checkout.isPending||uncertain} onClick={()=>{setReview(null);checkout.reset()}}>Back</Button><Button disabled={checkout.isPending||(review.quote.requires_below_cost_approval&&(!review.quote.can_approve_below_cost||!approved||!reason.trim()))} onClick={()=>checkout.mutate()}>{checkout.isPending?'Posting sale…':'Complete sale'}</Button></>}><div className="space-y-3">{review.quote.lines.map((l,i)=><div key={i} className="border-b pb-2 text-sm"><p>{l.product_name} · {amount(l.quantity)} {l.unit_code}</p><p className="font-semibold">{amount(l.total_mmk)} MMK</p>{l.cost_mmk!==undefined&&<p className="text-xs text-muted-foreground">Actual batch cost: {amount(l.cost_mmk)} MMK</p>}{l.below_cost&&<p className="text-destructive">Below actual cost — this sale records a loss.</p>}</div>)}{[['Total',review.quote.total_mmk],['Payment applied',review.quote.paid_mmk],['Cash change',review.quote.change_mmk],['Customer debt',review.quote.outstanding_mmk]].map(([l,v])=><p key={l} className="flex justify-between text-sm"><span>{l}</span><strong>{amount(v)} MMK</strong></p>)}{review.quote.requires_below_cost_approval&&<div className="rounded-lg border border-destructive/30 bg-destructive/5 p-3 text-sm" role="alert">{review.quote.can_approve_below_cost?<><p className="mb-2">Approval and its reason will be recorded with this sale.</p><label className="flex items-start gap-2"><input type="checkbox" className="mt-1 accent-primary" checked={approved} disabled={checkout.isPending||uncertain} onChange={e=>setApproved(e.target.checked)}/>I approve selling the flagged items below actual batch cost.</label>{!reason.trim()&&<p className="mt-2 text-destructive">Go back and enter an approval reason.</p>}</>:<p>A Super Admin must complete this sale or grant you permission to sell below cost.</p>}</div>}{checkout.error&&<p role="alert" className="text-sm text-destructive">{checkout.error.message}{uncertain&&' Retry this same checkout to retrieve its result without charging twice.'}</p>}</div></Modal>}</>
}
