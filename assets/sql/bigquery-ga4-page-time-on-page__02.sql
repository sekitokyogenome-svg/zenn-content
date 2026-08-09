-- 出典: BigQueryでGA4のページ別滞在時間を正しく集計する方法
-- 記事: articles/bigquery-ga4-page-time-on-page.md（ページ別の平均滞在時間を集計するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH engagement AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND event_name = 'user_engagement'
)
SELECT
  NET.REG_DOMAIN(page_location) AS domain,
  REGEXP_EXTRACT(page_location, r'^https?://[^/]+(/.*)') AS page_path,
  COUNT(*) AS engagement_events,
  ROUND(AVG(engagement_time_msec) / 1000, 1) AS avg_engagement_sec,
  ROUND(SUM(engagement_time_msec) / 1000, 1) AS total_engagement_sec
FROM engagement
WHERE engagement_time_msec IS NOT NULL
  AND engagement_time_msec > 0
GROUP BY domain, page_path
ORDER BY engagement_events DESC
LIMIT 50
