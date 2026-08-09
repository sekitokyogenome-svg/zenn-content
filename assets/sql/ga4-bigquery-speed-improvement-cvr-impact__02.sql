-- 出典: GA4×BigQueryでECサイトの速度改善がCVRに与えた影響を測定した
-- 記事: articles/ga4-bigquery-speed-improvement-cvr-impact.md（Step 1: GA4でページ速度関連のイベントを取得する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH web_vitals AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'metric_name') AS metric_name,
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value') AS metric_value,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
    device.category AS device_category
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'web_vitals'
)
SELECT
  metric_name,
  device_category,
  COUNT(*) AS sample_count,
  ROUND(APPROX_QUANTILES(metric_value, 100)[OFFSET(50)], 2) AS p50,
  ROUND(APPROX_QUANTILES(metric_value, 100)[OFFSET(75)], 2) AS p75,
  ROUND(APPROX_QUANTILES(metric_value, 100)[OFFSET(90)], 2) AS p90
FROM web_vitals
WHERE metric_name IN ('LCP', 'INP', 'CLS')
GROUP BY metric_name, device_category
ORDER BY metric_name, device_category
