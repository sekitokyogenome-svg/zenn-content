-- 出典: GA4×BigQueryでセッションIDを正しく定義する方法
-- 記事: articles/ga4-bigquery-session-id-definition.md（セッションごとのPV数）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH sessions AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
)
SELECT
  session_id,
  COUNTIF(event_name = 'page_view') AS page_views
FROM sessions
GROUP BY session_id
ORDER BY page_views DESC
LIMIT 20
