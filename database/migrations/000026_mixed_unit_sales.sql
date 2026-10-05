-- Preserve the current checkout implementation (including automatic IDs and
-- approval history); allow one line per product/unit and reserve FIFO quantities
-- across all lines during both quotation and posting.
DO $$ DECLARE definition text; before text;
BEGIN
 definition=pg_get_functiondef('app.pos_sale(jsonb,uuid,boolean,boolean,boolean)'::regprocedure);
 before=definition;
 definition=replace(definition, 'count(DISTINCT value->>''product_id'')', 'count(DISTINCT (value->>''product_id'',value->>''unit_code''))');
 definition=replace(definition, 'Use one cart line per product; choose its selling unit on that line.', 'Use one cart line per product and selling unit.');
 definition=replace(definition,'take=least(needed,stock.available_quantity);', $replacement$
   take=least(needed,stock.available_quantity-coalesce((
    SELECT sum((a->>'quantity')::numeric)
    FROM jsonb_array_elements(lines) l CROSS JOIN LATERAL jsonb_array_elements(l->'allocations') a
    WHERE a->>'batch_id'=stock.batch_id::text AND l->>'stock_bucket'=coalesce(x->>'stock_bucket','SELLABLE')
   ),0));
   IF take<=0 THEN CONTINUE; END IF;
$replacement$);
 IF definition=before OR strpos(definition,'IF take<=0 THEN CONTINUE; END IF;')=0 THEN RAISE EXCEPTION 'Unexpected checkout definition'; END IF;
 EXECUTE definition;
END $$;
