-- 出典: Claude Code × dbtでデータ変換パイプラインのテストコードを自動生成する
-- 記事: articles/claude-code-dbt-pipeline-test-generation.md（dbt × BigQueryの基本構成を整理する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- staging/stg_ga4_events.sql
SELECT
  event_date,
  event_name,
  user_pseudo_id,
  (SELECT value.int_value
   FROM UNNEST(event_params) AS ep
   WHERE ep.key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
