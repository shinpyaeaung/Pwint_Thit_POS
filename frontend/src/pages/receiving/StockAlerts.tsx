import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { DataTable } from '@/components/shared'
import { requestJSON } from '@/services/api'
import { amount } from '../purchases/types'
type Alert = {product_id:string;product_name:string;sku:string;unit:string;available:string;minimum_stock:string|null}
export function StockAlerts({status,warehouse,search}:{status:string;warehouse:string;search:string}) {
 const [page,setPage]=useState(1)
 const query=useQuery({queryKey:['inventory','alerts',status,warehouse,search,page],queryFn:({signal})=>requestJSON<{total:number;products:Alert[]}>(`/inventory/alerts?stock_status=${status}&warehouse_id=${warehouse}&q=${encodeURIComponent(search)}&page=${page}&page_size=20`,{signal})})
 return <><p className="my-3 text-sm text-muted-foreground">{warehouse?'Selected warehouse':'All warehouses combined'} · Active products, including products never stocked. Available stock excludes expired, damaged and reserved goods. Low stock means above zero and at or below the product’s minimum stock level.</p><DataTable caption={status==='low'?'Low stock products':'Out of stock products'} rows={query.data?.products||[]} rowKey={r=>r.product_id} loading={query.isPending} error={query.error?.message} pagination={{page,pageSize:20,total:query.data?.total||0,onPageChange:setPage}} columns={[{id:'product',header:'Product',cell:r=><div>{r.product_name}<p className="text-xs text-muted-foreground">{r.sku}</p></div>},{id:'available',header:'Available',cell:r=>`${amount(r.available)} ${r.unit}`},{id:'minimum',header:'Minimum stock',cell:r=>r.minimum_stock===null?'Not set':`${amount(r.minimum_stock)} ${r.unit}`}]} /></>
}
