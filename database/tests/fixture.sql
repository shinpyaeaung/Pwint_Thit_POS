INSERT INTO app.users(id,username,display_name,password_hash,role_code) VALUES
 ('00000000-0000-0000-0000-000000000001','owner','Owner','test-hash-not-a-real-password','SUPER_ADMIN'),
 ('00000000-0000-0000-0000-000000000002','staff','Staff','test-hash-not-a-real-password','STAFF_ADMIN');
INSERT INTO app.suppliers(id,code,name) VALUES ('00000000-0000-0000-0000-000000000010','SUP-1','Supplier');
INSERT INTO app.customers(id,code,name) VALUES ('00000000-0000-0000-0000-000000000011','CUS-1','Customer');
INSERT INTO app.warehouses(id,code,name) VALUES ('00000000-0000-0000-0000-000000000012','MAIN','Main');
INSERT INTO app.products(id,sku,name,base_unit_code) VALUES
 ('00000000-0000-0000-0000-000000000020','P-1','Bottles','BOTTLE'),
 ('00000000-0000-0000-0000-000000000021','P-2','Other','PIECE');
INSERT INTO app.product_units(product_id,unit_code,units_per_pack) VALUES ('00000000-0000-0000-0000-000000000020','CARTON',12);
INSERT INTO app.exchange_rates(id,currency_code,mmk_per_unit,effective_at,source,recorded_by) VALUES
 ('00000000-0000-0000-0000-000000000030','INR',25,now(),'fixture','00000000-0000-0000-0000-000000000001');
INSERT INTO app.purchases(id,purchase_number,supplier_id,purchased_at,currency_code,exchange_rate_id,mmk_per_unit,created_by) VALUES
 ('00000000-0000-0000-0000-000000000040','PUR-1','00000000-0000-0000-0000-000000000010',now(),'INR','00000000-0000-0000-0000-000000000030',25,'00000000-0000-0000-0000-000000000001');
INSERT INTO app.purchase_items(id,purchase_id,line_number,product_id,unit_code,quantity,units_per_pack,unit_price_original) VALUES
 ('00000000-0000-0000-0000-000000000041','00000000-0000-0000-0000-000000000040',1,'00000000-0000-0000-0000-000000000020','CARTON',1,12,10000);
INSERT INTO app.shipments(id,shipment_number,start_location,destination_warehouse_id,created_by) VALUES
 ('00000000-0000-0000-0000-000000000050','SH-1','Supplier city','00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000001');
INSERT INTO app.shipment_items(id,shipment_id,purchase_item_id,product_id,expected_quantity) VALUES
 ('00000000-0000-0000-0000-000000000051','00000000-0000-0000-0000-000000000050','00000000-0000-0000-0000-000000000041','00000000-0000-0000-0000-000000000020',12);
INSERT INTO app.goods_receiving(id,receipt_number,shipment_id,warehouse_id,received_at,received_by) VALUES
 ('00000000-0000-0000-0000-000000000060','REC-1','00000000-0000-0000-0000-000000000050','00000000-0000-0000-0000-000000000012',now(),'00000000-0000-0000-0000-000000000001');
INSERT INTO app.goods_receiving_items(id,goods_receiving_id,shipment_id,shipment_item_id,product_id,expected_quantity,received_quantity,damaged_quantity,batch_number) VALUES
 ('00000000-0000-0000-0000-000000000061','00000000-0000-0000-0000-000000000060','00000000-0000-0000-0000-000000000050','00000000-0000-0000-0000-000000000051','00000000-0000-0000-0000-000000000020',12,11,1,'BATCH-1');
INSERT INTO app.batches(id,product_id,receiving_item_id,batch_number,received_at,purchase_cost_mmk,transport_cost_mmk,sellable_quantity) VALUES
 ('00000000-0000-0000-0000-000000000070','00000000-0000-0000-0000-000000000020','00000000-0000-0000-0000-000000000061','BATCH-1',now(),250000,50000,10);
INSERT INTO app.sales(id,invoice_number,customer_id,warehouse_id,pricing_mode,sold_at,created_by) VALUES
 ('00000000-0000-0000-0000-000000000080','SALE-1','00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000012','RETAIL',now(),'00000000-0000-0000-0000-000000000001');
INSERT INTO app.sale_items(id,sale_id,line_number,product_id,unit_code,units_per_pack,quantity,unit_price_mmk) VALUES
 ('00000000-0000-0000-0000-000000000081','00000000-0000-0000-0000-000000000080',1,'00000000-0000-0000-0000-000000000020','BOTTLE',1,2,40000);
INSERT INTO app.sale_item_batches(id,sale_item_id,batch_id,product_id,quantity,unit_cost_mmk) VALUES
 ('00000000-0000-0000-0000-000000000082','00000000-0000-0000-0000-000000000081','00000000-0000-0000-0000-000000000070','00000000-0000-0000-0000-000000000020',2,30000);
INSERT INTO app.inventory(warehouse_id,batch_id,sellable_quantity,reserved_quantity,damaged_quantity) VALUES
 ('00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000070',10,2,1);
