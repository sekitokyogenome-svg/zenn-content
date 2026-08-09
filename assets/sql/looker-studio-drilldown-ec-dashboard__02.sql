-- 出典: Looker Studioでドリルダウン機能を使ったEC分析ダッシュボードを作る
-- 記事: articles/looker-studio-drilldown-ec-dashboard.md（NULL値の対策をする）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.ec_sales_drilldown` AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  IFNULL(items.item_category, '未分類') AS category,
  IFNULL(items.item_brand, 'ノーブランド') AS brand,
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
