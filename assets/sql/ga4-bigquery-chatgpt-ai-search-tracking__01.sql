-- 出典: AI検索時代のGA4活用術―ChatGPT流入をBigQueryで追跡する
-- 記事: articles/ga4-bigquery-chatgpt-ai-search-tracking.md（BigQueryでAI検索セッションを特定するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- AI検索エンジンからのセッションを日別に集計
WITH session_referrers AS (
  SELECT
    event_date,
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer') AS page_referrer
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name = 'session_start'
),

ai_sessions AS (
  SELECT
    *,
    CASE
      WHEN REGEXP_CONTAINS(page_referrer, r'chatgpt\.com|chat\.openai\.com') THEN 'ChatGPT'
      WHEN REGEXP_CONTAINS(page_referrer, r'perplexity\.ai') THEN 'Perplexity'
      WHEN REGEXP_CONTAINS(page_referrer, r'gemini\.google\.com') THEN 'Gemini'
      WHEN REGEXP_CONTAINS(page_referrer, r'copilot\.microsoft\.com') THEN 'Copilot'
      WHEN REGEXP_CONTAINS(page_referrer, r'claude\.ai') THEN 'Claude'
      ELSE NULL
    END AS ai_source
  FROM session_referrers
)

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  ai_source,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(session_id AS STRING))) AS sessions
FROM ai_sessions
WHERE ai_source IS NOT NULL
GROUP BY date, ai_source
ORDER BY date DESC, sessions DESC;
