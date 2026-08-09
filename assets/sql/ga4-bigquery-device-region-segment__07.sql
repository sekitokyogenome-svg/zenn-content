-- 出典: GA4×BigQueryでデバイス別・地域別セグメント分析をする
-- 記事: articles/ga4-bigquery-device-region-segment.md（OS別・ブラウザ別の分析）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  device.operating_system AS os,
  device.web_info.browser AS browser,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    )
  ) AS sessions,
  ROUND(AVG(
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'engagement_time_msec')
  ) / 1000, 1) AS avg_engagement_sec
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
GROUP BY os, browser
HAVING sessions >= 10
ORDER BY sessions DESC
LIMIT 20
