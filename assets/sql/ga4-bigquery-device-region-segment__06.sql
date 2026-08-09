-- 出典: GA4×BigQueryでデバイス別・地域別セグメント分析をする
-- 記事: articles/ga4-bigquery-device-region-segment.md（地域×デバイスのクロス分析）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  geo.region AS region,
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
  AND geo.country = 'Japan'
GROUP BY region, device_category
HAVING sessions >= 5
ORDER BY region, sessions DESC
