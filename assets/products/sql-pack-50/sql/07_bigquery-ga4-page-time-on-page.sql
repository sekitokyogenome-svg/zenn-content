-- 07. BigQueryでGA4のページ別滞在時間を正しく集計する方法（最後のページ問題への対処）
-- 用途: 最後のページ問題への対処
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH page_views AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    LEAD(event_timestamp) OVER (
      PARTITION BY user_pseudo_id,
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      ORDER BY event_timestamp
    ) AS next_event_timestamp
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND event_name = 'page_view'
)
SELECT
  REGEXP_EXTRACT(page_location, r'^https?://[^/]+(/.*)') AS page_path,
  COUNT(*) AS page_views,
  ROUND(AVG(
    CASE
      WHEN next_event_timestamp IS NOT NULL
      THEN (next_event_timestamp - event_timestamp) / 1000000
    END
  ), 1) AS avg_time_on_page_sec
FROM page_views
GROUP BY page_path
ORDER BY page_views DESC
LIMIT 50
