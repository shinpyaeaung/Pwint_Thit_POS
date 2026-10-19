-- name: MoneyAccountCreate :one
SELECT app.account_create(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
-- name: AccountEntryPost :one
SELECT app.account_entry_post(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
-- name: MoneyAccountOptions :one
SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'bank',bank) ORDER BY name),'[]')::jsonb FROM app.money_accounts;
-- name: MoneyAccounts :one
WITH accounts AS(SELECT a.id,a.name,a.bank,a.reference,coalesce(sum(e.amount_mmk),0) AS balance FROM app.money_accounts a LEFT JOIN app.account_entries e ON e.account_id=a.id GROUP BY a.id)
SELECT jsonb_build_object('total_mmk',coalesce((SELECT sum(balance) FROM accounts),0)::text,'accounts',coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'name',name,'bank',bank,'reference',reference,'balance_mmk',balance::text) ORDER BY name) FROM accounts),'[]'))::jsonb;
-- name: AccountHistory :one
WITH running AS(SELECT e.*,a.name AS account_name,u.display_name AS recorded_by_name,p.currency_code,p.amount_original::text AS original_amount,
 sum(e.amount_mmk) OVER(PARTITION BY e.account_id ORDER BY e.occurred_at,e.sequence ROWS UNBOUNDED PRECEDING)::text AS balance_mmk,
 EXISTS(SELECT 1 FROM app.account_entries r WHERE r.reverses_id=e.id) AS reversed
 FROM app.account_entries e JOIN app.money_accounts a ON a.id=e.account_id JOIN app.users u ON u.id=e.recorded_by LEFT JOIN app.payments p ON p.id=e.payment_id),
 filtered AS(SELECT * FROM running WHERE (sqlc.arg(account_id)::text='' OR account_id::text=sqlc.arg(account_id)) AND (sqlc.arg(kind)::text='' OR kind=sqlc.arg(kind)) AND (sqlc.arg(start_on)::text='' OR occurred_at>=sqlc.arg(start_on)::date::timestamp AT TIME ZONE 'Asia/Yangon') AND (sqlc.arg(end_on)::text='' OR occurred_at<(sqlc.arg(end_on)::date+1)::timestamp AT TIME ZONE 'Asia/Yangon')),
 page AS(SELECT * FROM filtered ORDER BY occurred_at DESC,sequence DESC LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'entries',coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'account_id',account_id,'account_name',account_name,'kind',kind,'amount_mmk',amount_mmk::text,'balance_mmk',balance_mmk,'sender',sender,'description',description,'occurred_at',occurred_at,'recorded_by',recorded_by_name,'reversed',reversed,'payment_id',payment_id,'currency_code',currency_code,'original_amount',original_amount) ORDER BY occurred_at DESC,sequence DESC) FROM page),'[]'))::jsonb;
