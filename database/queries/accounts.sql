-- name: MoneyAccountCreate :one
SELECT app.account_create(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
-- name: MoneyAccountUpdate :one
SELECT app.account_update(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
-- name: AccountEntryPost :one
SELECT app.account_entry_post(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
-- name: MoneyAccountOptions :one
SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'bank',bank) ORDER BY name),'[]')::jsonb FROM app.money_accounts WHERE is_active;
-- name: MoneyAccounts :one
WITH accounts AS(SELECT a.id,a.name,a.bank,a.reference,a.is_active,a.version,coalesce(sum(e.amount_mmk),0) AS balance FROM app.money_accounts a LEFT JOIN app.account_entries e ON e.account_id=a.id GROUP BY a.id)
SELECT jsonb_build_object('total_mmk',coalesce((SELECT sum(balance) FROM accounts),0)::text,'accounts',coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'name',name,'bank',bank,'reference',reference,'is_active',is_active,'version',version,'balance_mmk',balance::text) ORDER BY is_active DESC,name) FROM accounts),'[]'))::jsonb;
-- name: AccountHistory :one
WITH running AS(SELECT e.*,a.name AS account_name,u.display_name AS recorded_by_name,p.method AS p_method,p.reference_number AS p_reference,p.currency_code,p.amount_original::text AS original_amount,
 sum(e.amount_mmk) OVER(PARTITION BY e.account_id ORDER BY e.occurred_at,e.sequence ROWS UNBOUNDED PRECEDING)::text AS balance_mmk,
 EXISTS(SELECT 1 FROM app.account_entries r WHERE r.reverses_id=e.id) AS reversed
 FROM app.account_entries e JOIN app.money_accounts a ON a.id=e.account_id JOIN app.users u ON u.id=e.recorded_by LEFT JOIN app.payments p ON p.id=e.payment_id),
 filtered AS(SELECT * FROM running WHERE (sqlc.arg(account_id)::text='' OR account_id::text=sqlc.arg(account_id)) AND (sqlc.arg(kind)::text='' OR kind=sqlc.arg(kind)) AND (sqlc.arg(start_on)::text='' OR occurred_at>=sqlc.arg(start_on)::date::timestamp AT TIME ZONE 'Asia/Yangon') AND (sqlc.arg(end_on)::text='' OR occurred_at<(sqlc.arg(end_on)::date+1)::timestamp AT TIME ZONE 'Asia/Yangon')),
 page AS(SELECT * FROM filtered ORDER BY occurred_at DESC,sequence DESC LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM filtered),'entries',coalesce((SELECT jsonb_agg(jsonb_build_object('id',id,'account_id',account_id,'account_name',account_name,'kind',kind,'amount_mmk',amount_mmk::text,'balance_mmk',balance_mmk,'sender',sender,'description',description,'occurred_at',occurred_at,'payer',payer,'payee',payee,'method',coalesce(p_method,method),'reference',coalesce(p_reference,reference),'recorded_by',recorded_by_name,'reversed',reversed,'payment_id',payment_id,'currency_code',currency_code,'original_amount',original_amount) ORDER BY occurred_at DESC,sequence DESC) FROM page),'[]'))::jsonb;
-- name: CreditorCreate :one
SELECT app.creditor_create(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
-- name: CreditorRepay :one
SELECT app.creditor_repay(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
-- name: CreditorOptions :one
SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name),'[]')::jsonb FROM app.creditors;
-- name: Creditors :one
SELECT coalesce(jsonb_agg(doc ORDER BY name),'[]')::jsonb FROM (
 SELECT c.name,jsonb_build_object('id',c.id,'name',c.name,'contact',c.contact,
 'funded_mmk',coalesce(sum(e.amount_mmk) FILTER(WHERE r.payment_id IS NULL AND v.payment_id IS NULL),0)::text,
 'settled_mmk',coalesce(-sum(e.amount_mmk) FILTER(WHERE r.payment_id IS NOT NULL OR v.payment_id IS NOT NULL),0)::text,
 'outstanding_mmk',coalesce(sum(e.amount_mmk),0)::text) doc
 FROM app.creditors c LEFT JOIN app.account_entries e ON e.creditor_id=c.id LEFT JOIN app.creditor_repayments r ON r.payment_id=e.payment_id LEFT JOIN app.creditor_repayment_reversals v ON v.payment_id=e.payment_id GROUP BY c.id
) creditors;
-- name: CreditorHistory :one
WITH running AS (
 SELECT e.*,sum(e.amount_mmk) OVER(ORDER BY e.occurred_at,e.sequence ROWS UNBOUNDED PRECEDING) AS outstanding,p.currency_code,p.amount_original
 FROM app.account_entries e LEFT JOIN app.payments p ON p.id=e.payment_id WHERE e.creditor_id=sqlc.arg(creditor_id)::uuid
), page AS (SELECT * FROM running ORDER BY occurred_at DESC,sequence DESC LIMIT sqlc.arg(page_size)::int OFFSET sqlc.arg(page_offset)::int)
SELECT jsonb_build_object('total',(SELECT count(*) FROM running),'entries',coalesce((SELECT jsonb_agg(jsonb_build_object(
 'id',id,'amount_mmk',amount_mmk::text,'balance_mmk',outstanding::text,'occurred_at',occurred_at,'payer',payer,'payee',payee,
 'payment_id',payment_id,'is_repayment',EXISTS(SELECT 1 FROM app.creditor_repayments r WHERE r.payment_id=page.payment_id),'reversed',EXISTS(SELECT 1 FROM app.creditor_repayment_reversals r WHERE r.original_payment_id=page.payment_id),'method',method,'reference',reference,'description',description,'currency_code',currency_code,'original_amount',amount_original::text
 ) ORDER BY occurred_at DESC,sequence DESC) FROM page),'[]'))::jsonb;
-- name: CreditorRepaymentReverse :one
SELECT app.creditor_repayment_reverse(sqlc.arg(data)::jsonb,sqlc.arg(actor)::uuid)::uuid;
