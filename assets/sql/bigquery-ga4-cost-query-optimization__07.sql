-- 出典: BigQueryでGA4データのコスト管理・クエリ最適化入門
-- 記事: articles/bigquery-ga4-cost-query-optimization.md（テクニック3：中間テーブルやビューを活用する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 中間テーブルとして保存
CREATE OR REPLACE TABLE `your-project.staging.sessions_202603` AS
SELECT
  event_date,
  CONCAT(
    user_pseudo_id, '.',
    CAST(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  user_pseudo_id,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
