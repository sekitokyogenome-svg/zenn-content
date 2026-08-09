-- 出典: GA4×BigQueryでデバイス別・地域別セグメント分析をする
-- 記事: articles/ga4-bigquery-device-region-segment.md（PIVOT的なデバイス別集計（日別×デバイス））
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH daily_device AS (
  SELECT
    event_date,
    device.category AS device_category,
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
  GROUP BY event_date, device_category
)
SELECT
  event_date,
  SUM(CASE WHEN device_category = 'desktop' THEN sessions ELSE 0 END) AS desktop,
  SUM(CASE WHEN device_category = 'mobile' THEN sessions ELSE 0 END) AS mobile,
  SUM(CASE WHEN device_category = 'tablet' THEN sessions ELSE 0 END) AS tablet,
  SUM(sessions) AS total
FROM daily_device
GROUP BY event_date
ORDER BY event_date
