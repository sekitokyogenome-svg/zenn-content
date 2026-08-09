-- 421. AI検索時代のGA4活用術―ChatGPT流入をBigQueryで追跡する（AI検索流入のトレンド監視）
-- 用途: AI検索流入のトレンド監視
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK) AS week_start,
  COUNTIF(REGEXP_CONTAINS(
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer'),
    r'chatgpt\.com|chat\.openai\.com|perplexity\.ai|gemini\.google\.com|copilot\.microsoft\.com|claude\.ai'
  )) AS ai_search_sessions,
  COUNT(*) AS total_sessions,
  ROUND(SAFE_DIVIDE(
    COUNTIF(REGEXP_CONTAINS(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer'),
      r'chatgpt\.com|chat\.openai\.com|perplexity\.ai|gemini\.google\.com|copilot\.microsoft\.com|claude\.ai'
    )),
    COUNT(*)
  ) * 100, 2) AS ai_search_pct
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'session_start'
GROUP BY week_start
ORDER BY week_start;
