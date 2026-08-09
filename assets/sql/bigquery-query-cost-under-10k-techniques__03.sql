-- 出典: BigQueryのクエリコストを月1万円以下に抑える7つの実践テクニック
-- 記事: articles/bigquery-query-cost-under-10k-techniques.md（テクニック4：マテリアライズドビューで集計コストを自動化する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- セッション別流入元サマリーのマテリアライズドビュー例
CREATE MATERIALIZED VIEW `${PROJECT}.${DATASET}.mv_session_traffic`
AS
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'session_start'
GROUP BY
  event_date,
  traffic_medium,
  traffic_source
