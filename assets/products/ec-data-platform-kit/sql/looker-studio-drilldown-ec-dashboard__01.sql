-- Looker Studioでドリルダウン機能を使ったEC分析ダッシュボードを作る
-- 用途: ステップ1: データソースの準備
-- 必要テーブル: ec_sales_drilldown, events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.ec_sales_drilldown` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  items.item_category AS category,
  items.item_brand AS brand,
  items.item_name AS product_name,
  device.category AS device_type,
  traffic_source.source AS source,
  traffic_source.medium AS medium,
  items.quantity AS quantity,
  items.item_revenue AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS items
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY))
