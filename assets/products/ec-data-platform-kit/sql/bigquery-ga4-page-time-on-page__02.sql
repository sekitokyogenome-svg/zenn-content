-- BigQueryでGA4のページ別滞在時間を正しく集計する方法
-- 用途: ページ別の平均滞在時間を集計するSQL
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
