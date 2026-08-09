-- 50. GA4×BigQueryでコンバージョン経路を分析するSQL（ファーストタッチ分析：最初に見たページ）
-- 用途: ファーストタッチ分析：最初に見たページ
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_first_page AS (
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
      ORDER BY event_timestamp
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
  f.page_path AS first_touch_page,
  COUNT(*) AS cv_sessions
FROM session_first_page f
INNER JOIN cv_sessions c ON f.session_id = c.session_id
WHERE f.rn = 1
GROUP BY first_touch_page
ORDER BY cv_sessions DESC
LIMIT 20
