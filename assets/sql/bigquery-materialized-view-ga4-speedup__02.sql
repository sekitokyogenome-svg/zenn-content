-- 出典: BigQueryのマテリアライズドビューでGA4集計クエリを高速化した
-- 記事: articles/bigquery-materialized-view-ga4-speedup.md（GA4のBigQueryエクスポートテーブル構造を理解する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 流入元の取得方法
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX >= '20250601'
  AND event_name = 'session_start'
