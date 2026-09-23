INSERT INTO app.permissions(code,description,is_sensitive) VALUES
 ('products.create','Create products',false),('products.update','Update products',false),
 ('purchases.view','View purchases',false),('purchases.create','Create purchases',false),
 ('purchases.view_cost','View supplier purchase costs',true),
 ('sales.discount','Apply approved sales discounts',true),
 ('finance.view_profit','View profit reports',true),('finance.view_landed_cost','View landed costs',true),
 ('reports.view','View general reports',false);
-- Preserve existing grants when introducing the finer-grained vocabulary.
INSERT INTO app.user_permissions(user_id,permission_code,granted_by)
SELECT up.user_id,m.new_code,up.granted_by FROM app.user_permissions up JOIN (VALUES
 ('products.manage','products.create'),('products.manage','products.update'),
 ('purchases.manage','purchases.view'),('purchases.manage','purchases.create'),
 ('costs.view_purchase','purchases.view_cost'),('costs.view_landed','finance.view_landed_cost'),
 ('reports.profit','finance.view_profit'),('reports.sales','reports.view'),('reports.inventory','reports.view'),
 ('sales.large_discount','sales.discount')
) AS m(old_code,new_code) ON up.permission_code=m.old_code ON CONFLICT DO NOTHING;
CREATE TABLE app.login_throttles (
 key_hash bytea PRIMARY KEY CHECK(octet_length(key_hash)=32),
 attempts integer NOT NULL CHECK(attempts>0),
 window_started_at timestamptz NOT NULL DEFAULT now(),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX login_throttles_window ON app.login_throttles(window_started_at);
CREATE TRIGGER z_touch_updated_at BEFORE UPDATE ON app.login_throttles FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();
