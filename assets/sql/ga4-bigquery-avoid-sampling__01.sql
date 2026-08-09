-- 出典: BigQueryでGA4のサンプリングを回避して正確な数値を出す
-- 記事: articles/ga4-bigquery-avoid-sampling.md（BigQueryなら100%のデータで分析できる）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
GROUP BY event_date, medium
ORDER BY event_date, sessions DESC
