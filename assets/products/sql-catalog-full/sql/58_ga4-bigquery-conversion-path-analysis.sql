-- 58. GA4×BigQueryでコンバージョン経路を分析するSQL（よく通るコンバージョン経路をランキングする）
-- 用途: よく通るコンバージョン経路をランキングする
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH all_events AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_name,
    event_timestamp,
    REGEXP_EXTRACT(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'page_location'),
      r'https?://[^/]+(/.*)') AS page_path
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
),
cv_sessions AS (
  SELECT DISTINCT session_id
  FROM all_events
  WHERE event_name = 'purchase'
),
cv_paths AS (
  SELECT
    a.session_id,
    STRING_AGG(a.page_path, ' → ' ORDER BY a.event_timestamp) AS path
  FROM all_events a
  INNER JOIN cv_sessions c ON a.session_id = c.session_id
  WHERE a.event_name = 'page_view'
  GROUP BY a.session_id
)
SELECT
  path,
  COUNT(*) AS session_count
FROM cv_paths
GROUP BY path
ORDER BY session_count DESC
LIMIT 20
