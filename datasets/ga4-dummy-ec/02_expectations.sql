-- 仕込んだ罠の期待値（生成SQLを流した直後に実行。全部通れば生成は想定どおり）
-- 架空データ。決定的に生成されるため、数値は毎回同じ
ASSERT (SELECT COUNT(*) FROM `your-project.dummy_ga4_ec.events_all` WHERE event_name='session_start') = 4058 AS 'sessions';
ASSERT (SELECT COUNT(*) FROM `your-project.dummy_ga4_ec.events_all` WHERE event_name='purchase') = 443 AS 'purchase rows incl. 5 dups';
ASSERT (SELECT COUNT(DISTINCT ecommerce.transaction_id) FROM `your-project.dummy_ga4_ec.events_all` WHERE event_name='purchase') = 429 AS 'T1 distinct txn';
ASSERT (SELECT COUNTIF(ecommerce.transaction_id IS NULL) FROM `your-project.dummy_ga4_ec.events_all` WHERE event_name='purchase') = 9 AS 'T2 null txn';
ASSERT (SELECT SUM(ecommerce.purchase_revenue) FROM `your-project.dummy_ga4_ec.events_all` WHERE event_name='purchase') = 3238700 AS 'raw revenue (dups included)';
