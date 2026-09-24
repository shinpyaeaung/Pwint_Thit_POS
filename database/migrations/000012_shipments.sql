ALTER TABLE app.shipments ADD COLUMN version bigint NOT NULL DEFAULT 1 CHECK(version>0);
ALTER TABLE app.shipments ADD COLUMN request_id uuid UNIQUE;
ALTER TABLE app.transportation_stages ADD COLUMN request_id uuid UNIQUE;
ALTER TABLE app.shipment_expenses ADD COLUMN request_id uuid UNIQUE;
ALTER TABLE app.shipment_expenses ADD COLUMN notes text;
ALTER TABLE app.shipment_expenses ADD COLUMN voided_at timestamptz;
ALTER TABLE app.shipment_expenses ADD COLUMN void_reason text;
ALTER TABLE app.shipment_expenses ADD CONSTRAINT expense_void_reason CHECK((voided_at IS NULL)=(void_reason IS NULL));
CREATE INDEX shipment_page ON app.shipments(created_at DESC,id);
CREATE INDEX shipment_expense_page ON app.shipment_expenses(shipment_id,created_at,id);
INSERT INTO app.permissions(code,description,is_sensitive) VALUES('shipments.view_cost','View transportation and shipment expense amounts',true);
INSERT INTO app.user_permissions(user_id,permission_code,granted_by) SELECT user_id,'shipments.view_cost',granted_by FROM app.user_permissions WHERE permission_code='finance.view_landed_cost';
CREATE FUNCTION app.shipment_document(s app.shipments, costs boolean) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('id',s.id,'shipment_number',s.shipment_number,'start_location',s.start_location,'destination_warehouse_id',s.destination_warehouse_id,
 'destination_name',(SELECT name FROM app.warehouses WHERE id=s.destination_warehouse_id),'status',s.status,'shipped_at',s.shipped_at,'expected_arrival_at',s.expected_arrival_at,'arrived_at',s.arrived_at,'notes',s.notes,'version',s.version::text,'costs_finalized_at',s.costs_finalized_at,'can_view_cost',costs,
 'stage_count',(SELECT count(*) FROM app.transportation_stages WHERE shipment_id=s.id),'expense_count',(SELECT count(*) FROM app.shipment_expenses WHERE shipment_id=s.id AND voided_at IS NULL),
 'last_destination',(SELECT destination FROM app.transportation_stages WHERE shipment_id=s.id ORDER BY stage_number DESC LIMIT 1))
 || CASE WHEN costs THEN jsonb_build_object('transport_total_mmk',(SELECT COALESCE(sum(total_mmk),0)::text FROM app.transportation_stages WHERE shipment_id=s.id),'expense_total_mmk',(SELECT COALESCE(sum(amount_mmk),0)::text FROM app.shipment_expenses WHERE shipment_id=s.id AND voided_at IS NULL)) ELSE '{}'::jsonb END
$$;
CREATE FUNCTION app.stage_document(t app.transportation_stages, costs boolean) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('id',t.id,'stage_number',t.stage_number,'start_location',t.start_location,'destination',t.destination,'provider_name',t.provider_name,'transportation_type',t.transportation_type,'vehicle_information',t.vehicle_information,'departed_at',t.departed_at,'arrived_at',t.arrived_at,'notes',t.notes,
 'payment_status',CASE WHEN paid.amount>=t.total_mmk THEN 'PAID' WHEN paid.amount>0 THEN 'PARTIALLY_PAID' ELSE 'UNPAID' END)
 || CASE WHEN costs THEN jsonb_build_object('transportation_fee_mmk',t.transportation_fee_mmk::text,'loading_fee_mmk',t.loading_fee_mmk::text,'unloading_fee_mmk',t.unloading_fee_mmk::text,'other_fee_mmk',t.other_fee_mmk::text,'total_mmk',t.total_mmk::text,'paid_mmk',paid.amount::text) ELSE '{}'::jsonb END
 FROM (SELECT COALESCE(sum(a.applied_mmk),0) amount FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id WHERE a.transportation_stage_id=t.id AND p.status='POSTED' AND p.direction='OUT') paid
$$;
CREATE FUNCTION app.shipment_expense_document(e app.shipment_expenses,costs boolean) RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object('id',e.id,'category',e.category,'description',e.description,'incurred_at',e.incurred_at,'notes',e.notes,'currency_code',e.currency_code,'voided_at',e.voided_at,'void_reason',e.void_reason,
 'payment_status',CASE WHEN paid.amount>=e.amount_mmk THEN 'PAID' WHEN paid.amount>0 THEN 'PARTIALLY_PAID' ELSE 'UNPAID' END)
 || CASE WHEN costs THEN jsonb_build_object('amount_original',e.amount_original::text,'mmk_per_unit',e.mmk_per_unit::text,'amount_mmk',e.amount_mmk::text,'paid_mmk',paid.amount::text) ELSE '{}'::jsonb END
 FROM (SELECT COALESCE(sum(a.applied_mmk),0) amount FROM app.payment_allocations a JOIN app.payments p ON p.id=a.payment_id WHERE a.shipment_expense_id=e.id AND p.status='POSTED' AND p.direction='OUT') paid
$$;
