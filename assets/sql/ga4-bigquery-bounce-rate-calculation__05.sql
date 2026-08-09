-- 出典: BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）
-- 記事: articles/ga4-bigquery-bounce-rate-calculation.md（チャネル別の直帰率を比較する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH session_channel AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    MAX(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'session_engaged')
    ) AS session_engaged
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'session_start'
  GROUP BY session_id, medium
)
SELECT
  IFNULL(medium, '(none)') AS medium,
  COUNT(*) AS sessions,
  ROUND(
    COUNTIF(session_engaged != '1' OR session_engaged IS NULL)
    / COUNT(*) * 100, 2
  ) AS bounce_rate_percent
FROM session_channel
GROUP BY medium
ORDER BY sessions DESC
