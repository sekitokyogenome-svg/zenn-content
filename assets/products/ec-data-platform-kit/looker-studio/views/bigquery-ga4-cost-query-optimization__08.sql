-- BigQueryでGA4データのコスト管理・クエリ最適化入門
-- 出典: articles/bigquery-ga4-cost-query-optimization.md

CREATE OR REPLACE TABLE `your-project.staging.sessions_partitioned`
PARTITION BY event_date_parsed
CLUSTER BY medium
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date_parsed,
  CONCAT(
    user_pseudo_id, '.',
    CAST(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  collected_traffic_source.manual_medium AS medium,
  user_pseudo_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260101' AND '20260330'
  AND event_name = 'session_start'
