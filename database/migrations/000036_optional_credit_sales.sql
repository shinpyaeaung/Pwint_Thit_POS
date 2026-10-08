-- Explicit credit consent is part of the checkout request and quote snapshot.
-- Existing invoices and their idempotent replay path remain unchanged.
DO $$ DECLARE definition text; needle text;
BEGIN
 definition=pg_get_functiondef('app.pos_sale(jsonb,uuid,boolean,boolean,boolean)'::regprocedure);
 needle='IF debt>0 THEN';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Unexpected POS credit calculation'; END IF;
 definition=replace(definition,needle,$patch$IF debt>0 AND NOT coalesce((d->>'sell_on_credit')::boolean,false) THEN
 RAISE EXCEPTION 'pos: Full payment is required. Select Sell on Credit to leave a customer balance.' USING ERRCODE='23514';
 END IF;
 IF debt>0 THEN$patch$);
 needle='''outstanding_mmk'',debt::text';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'Unexpected POS invoice document'; END IF;
 definition=replace(definition,needle,'''sell_on_credit'',coalesce((d->>''sell_on_credit'')::boolean,false),'||needle);
 EXECUTE definition;
END $$;
