-- 出典: GA4×BigQueryでコンバージョン経路を分析するSQL
-- 記事: articles/ga4-bigquery-conversion-path-analysis.md（ラストタッチ分析：コンバージョン直前のページ）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH session_last_page AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_name,
    REGEXP_EXTRACT(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'page_location'),
      r'https?://[^/]+(/.*)') AS page_path,
    ROW_NUMBER() OVER (
      PARTITION BY
        CONCAT(
          user_pseudo_id, '.',
          CAST(
            (SELECT value.int_value
             FROM UNNEST(event_params)
             WHERE key = 'ga_session_id') AS STRING))
      ORDER BY event_timestamp DESC
    ) AS rn
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'page_view'
),
cv_sessions AS (
  SELECT DISTINCT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'purchase'
)
SELECT
  l.page_path AS last_touch_page,
  COUNT(*) AS cv_sessions
FROM session_last_page l
INNER JOIN cv_sessions c ON l.session_id = c.session_id
WHERE l.rn = 1
GROUP BY last_touch_page
ORDER BY cv_sessions DESC
LIMIT 20
