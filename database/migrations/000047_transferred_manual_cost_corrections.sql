-- Follow immutable transfer ancestry so manually entered stock remains correctable
-- after moving warehouses. Purchase-origin stock keeps its existing controls.
CREATE FUNCTION app.is_manual_stock_lineage(batch uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
 WITH RECURSIVE lineage AS (
  SELECT id,source_batch_id,manual_stock_entry_id FROM app.batches WHERE id=batch
  UNION
  SELECT b.id,b.source_batch_id,b.manual_stock_entry_id FROM app.batches b JOIN lineage l ON b.id=l.source_batch_id
 ) SELECT EXISTS(SELECT 1 FROM lineage WHERE manual_stock_entry_id IS NOT NULL)
$$;
DO $$ DECLARE definition text;
BEGIN
 definition=pg_get_functiondef('app.correct_manual_stock_cost(jsonb,uuid)'::regprocedure);
 IF strpos(definition,'source.manual_stock_entry_id IS NULL')=0 THEN RAISE EXCEPTION 'Unexpected manual cost correction definition'; END IF;
 definition=replace(definition,'source.manual_stock_entry_id IS NULL','NOT app.is_manual_stock_lineage(source.id)');
 definition=replace(definition,'Choose a costed batch created with Add existing stock.','Choose a costed manual-stock batch or its warehouse-transfer descendant.');
 EXECUTE definition;
END $$;
