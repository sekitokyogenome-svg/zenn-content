-- 架空のGA4 EC風ダミーデータ生成（2026-09-01〜09-30 / 2,500ユーザー候補）
-- 実データではない。SQL検証専用。乱数は FARM_FINGERPRINT で決定的（何度流しても同じ結果）
-- 実行先: your-project.dummy_ga4_ec.events_all （asia-northeast1）
-- 仕込んだ罠（期待値は 02_expectations.sql の ASSERT で検証する）:
--  T1 同一 transaction_id の purchase 重複 / T2 transaction_id が NULL の purchase
--  T3 ga_session_id がユーザー間で衝突 / T4 purchase_revenue は円、_in_usd は USD
CREATE OR REPLACE TABLE `your-project.dummy_ga4_ec.events_all`
OPTIONS (description='架空データ。実データではない') AS
WITH s AS (
  SELECT d, i,
    1 + MOD(ABS(FARM_FINGERPRINT(CONCAT('u', d, '-', i))), 2500) AS uid,
    1700000000 + MOD(ABS(FARM_FINGERPRINT(CONCAT('g', d, '-', i))), 200) AS ga_session_id,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('c', d, '-', i))), 100) AS rc,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('v', d, '-', i))), 100) AS rv,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('a', d, '-', i))), 100) AS ra,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('b', d, '-', i))), 100) AS rb,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('p', d, '-', i))), 100) AS rp,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('k', d, '-', i))), 12) AS sku,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('q', d, '-', i))), 2) + 1 AS qty,
    MOD(ABS(FARM_FINGERPRINT(CONCAT('t', d, '-', i))), 50000) AS sec
  FROM UNNEST(GENERATE_ARRAY(0, 29)) AS d,
       UNNEST(GENERATE_ARRAY(1, 160)) AS i
  WHERE MOD(ABS(FARM_FINGERPRINT(CONCAT('n', d, '-', i))), 100) < 85
),
s2 AS (
  SELECT *,
    CASE WHEN rc < 20 THEN 'google' WHEN rc < 50 THEN 'google' WHEN rc < 75 THEN '(direct)'
         WHEN rc < 85 THEN 'yahoo' ELSE 'newsletter' END AS src,
    CASE WHEN rc < 20 THEN 'cpc' WHEN rc < 50 THEN 'organic' WHEN rc < 75 THEN '(none)'
         WHEN rc < 85 THEN 'cpc' ELSE 'email' END AS med,
    CASE WHEN rc < 20 THEN 'brand_search' WHEN rc < 50 THEN '(organic)' WHEN rc < 75 THEN '(direct)'
         WHEN rc < 85 THEN 'ly_ads_sale' ELSE 'mail_autumn' END AS camp,
    -- 流入元ごとにカート追加率を変える（direct高め / organic低め）
    CASE WHEN rc < 20 THEN 30 WHEN rc < 50 THEN 20 WHEN rc < 75 THEN 45 WHEN rc < 85 THEN 15 ELSE 40 END AS p_atc,
    1000 + sku * 700 AS price
  FROM s
),
stages AS (
  SELECT s2.*, st.name, st.ord FROM s2, UNNEST([
    STRUCT('session_start' AS name, 0 AS ord), STRUCT('page_view', 1),
    STRUCT('view_item', 2), STRUCT('add_to_cart', 3),
    STRUCT('begin_checkout', 4), STRUCT('purchase', 5)]) AS st
  WHERE st.ord <= 1
     OR (st.ord = 2 AND rv < 80)
     OR (st.ord = 3 AND rv < 80 AND ra < p_atc)
     OR (st.ord = 4 AND rv < 80 AND ra < p_atc AND rb < 60)
     OR (st.ord = 5 AND rv < 80 AND ra < p_atc AND rb < 60 AND rp < 70)
),
base AS (
  SELECT *,
    FORMAT_DATE('%Y%m%d', DATE_ADD(DATE '2026-09-01', INTERVAL d DAY)) AS event_date,
    UNIX_MICROS(TIMESTAMP(DATE_ADD(DATE '2026-09-01', INTERVAL d DAY))) + (sec + ord * 40) * 1000000 AS ts,
    CONCAT('T', FORMAT('%02d', d), '-', FORMAT('%03d', i)) AS txn
  FROM stages
)
SELECT
  event_date,
  ts + ord AS event_timestamp,
  name AS event_name,
  [STRUCT('ga_session_id' AS key, STRUCT(CAST(NULL AS STRING) AS string_value, CAST(ga_session_id AS INT64) AS int_value, CAST(NULL AS FLOAT64) AS float_value, CAST(NULL AS FLOAT64) AS double_value) AS value),
   STRUCT('page_location', STRUCT(CONCAT('https://shop.example.invalid/', IF(ord >= 2, CONCAT('item/SKU-', FORMAT('%02d', sku)), ''), '?utm_source=', src), NULL, NULL, NULL)),
   STRUCT('currency', STRUCT('JPY', NULL, NULL, NULL))] AS event_params,
  CONCAT('dummy_', FORMAT('%05d', uid)) AS user_pseudo_id,
  CAST(NULL AS STRING) AS user_id,
  STRUCT(IF(MOD(uid, 10) < 6, 'mobile', 'desktop') AS category) AS device,
  STRUCT('Japan' AS country) AS geo,
  STRUCT(src AS source, med AS medium, camp AS name) AS traffic_source,
  STRUCT(src AS manual_source, med AS manual_medium, camp AS manual_campaign_name, CAST(NULL AS STRING) AS gclid) AS collected_traffic_source,
  STRUCT(
    IF(med IN ('cpc','email'),
       STRUCT(CAST(NULL AS STRING) AS campaign_id, camp AS campaign_name, src AS source, med AS medium, CAST(NULL AS STRING) AS term, CAST(NULL AS STRING) AS content, CAST(NULL AS STRING) AS source_platform),
       CAST(NULL AS STRUCT<campaign_id STRING, campaign_name STRING, source STRING, medium STRING, term STRING, content STRING, source_platform STRING>)) AS manual_campaign,
    STRUCT(CAST(NULL AS STRING) AS campaign_id, camp AS campaign_name, src AS source, med AS medium, 'Manual' AS source_platform,
           CASE med WHEN 'cpc' THEN 'Paid Search' WHEN 'organic' THEN 'Organic Search' WHEN 'email' THEN 'Email' ELSE 'Direct' END AS default_channel_group) AS cross_channel_campaign
  ) AS session_traffic_source_last_click,
  IF(name = 'purchase',
     STRUCT(IF(MOD(i, 37) = 0, CAST(NULL AS STRING), txn) AS transaction_id,
            CAST(price * qty AS FLOAT64) AS purchase_revenue,
            ROUND(price * qty / 150, 2) AS purchase_revenue_in_usd,
            qty AS total_item_quantity),
     CAST(NULL AS STRUCT<transaction_id STRING, purchase_revenue FLOAT64, purchase_revenue_in_usd FLOAT64, total_item_quantity INT64>)) AS ecommerce,
  IF(ord >= 2,
     [STRUCT(CONCAT('SKU-', FORMAT('%02d', sku)) AS item_id, CONCAT('ダミー商品', FORMAT('%02d', sku)) AS item_name, CAST(price AS FLOAT64) AS price, qty AS quantity)],
     CAST([] AS ARRAY<STRUCT<item_id STRING, item_name STRING, price FLOAT64, quantity INT64>>)) AS items
FROM base;

-- T1: 重複 purchase（同一 transaction_id を5件だけ複製）
INSERT INTO `your-project.dummy_ga4_ec.events_all`
SELECT * FROM `your-project.dummy_ga4_ec.events_all`
WHERE event_name = 'purchase' AND ecommerce.transaction_id IS NOT NULL
ORDER BY ecommerce.transaction_id LIMIT 5;
