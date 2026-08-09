-- 出典: BigQueryのパーティション・クラスタリングでGA4クエリを高速化する
-- 記事: articles/bigquery-partition-clustering-ga4-optimization.md（集計テーブルにパーティションを設定する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

CREATE OR REPLACE TABLE `your-project.mart.mart_daily_sessions`
PARTITION BY event_date
CLUSTER BY session_medium, device_category
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  IFNULL(collected_traffic_source.manual_medium, '(none)') AS session_medium,
  device.category AS device_category,
  geo.country AS country
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
  AND event_name = 'session_start'
