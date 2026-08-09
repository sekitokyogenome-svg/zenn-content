-- 419. AI検索時代のGA4活用術―ChatGPT流入をBigQueryで追跡する（AI検索 vs オーガニック vs ダイレクトの行動比較）
-- 用途: AI検索 vs オーガニック vs ダイレクトの行動比較
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_base AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    event_name,
    event_timestamp,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer') AS page_referrer,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium') AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),

session_channel AS (
  SELECT
    user_pseudo_id,
    session_id,
    CASE
      WHEN REGEXP_CONTAINS(
        MAX(IF(event_name = 'session_start', page_referrer, NULL)),
        r'chatgpt\.com|chat\.openai\.com|perplexity\.ai|gemini\.google\.com|copilot\.microsoft\.com|claude\.ai'
      ) THEN 'AI Search'
      WHEN MAX(IF(event_name = 'session_start', medium, NULL)) = 'organic' THEN 'Organic Search'
      WHEN MAX(IF(event_name = 'session_start', page_referrer, NULL)) IS NULL THEN 'Direct'
      ELSE 'Other'
    END AS channel,
    COUNT(DISTINCT IF(event_name = 'page_view', page_location, NULL)) AS pages_per_session,
    TIMESTAMP_DIFF(
      TIMESTAMP_MICROS(MAX(event_timestamp)),
      TIMESTAMP_MICROS(MIN(event_timestamp)),
      SECOND
    ) AS session_duration_sec,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_conversion
  FROM session_base
  GROUP BY user_pseudo_id, session_id
)

SELECT
  channel,
  COUNT(*) AS sessions,
  ROUND(AVG(pages_per_session), 1) AS avg_pages_per_session,
  ROUND(AVG(session_duration_sec), 0) AS avg_session_duration_sec,
  ROUND(SAFE_DIVIDE(SUM(has_conversion), COUNT(*)) * 100, 2) AS cvr_pct
FROM session_channel
WHERE channel IN ('AI Search', 'Organic Search', 'Direct')
GROUP BY channel
ORDER BY sessions DESC;
