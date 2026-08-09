-- 118. BigQueryのパーティション・クラスタリングでGA4クエリを高速化する（パターン2：ページビュー集計テーブル）
-- 用途: パターン2：ページビュー集計テーブル
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE TABLE `your-project.mart.mart_page_views`
PARTITION BY event_date
CLUSTER BY page_path, device_category
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  user_pseudo_id,
  REGEXP_EXTRACT(
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
    r'^https?://[^/]+(/.*)') AS page_path,
  device.category AS device_category
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
  AND event_name = 'page_view'
