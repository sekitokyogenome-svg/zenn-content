-- 24. EC商品ページの離脱率をGA4×BigQueryで分析して改善につなげた事例
-- 用途: 基本SQL：商品ページ別の離脱率を算出する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_pages AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    event_timestamp
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'page_view'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
last_page_per_session AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    ARRAY_AGG(page_location ORDER BY event_timestamp DESC LIMIT 1)[OFFSET(0)] AS exit_page
  FROM session_pages
  GROUP BY user_pseudo_id, ga_session_id
),
product_page_views AS (
  SELECT
    sp.user_pseudo_id,
    sp.ga_session_id,
    sp.page_location,
    CASE WHEN lp.exit_page = sp.page_location THEN 1 ELSE 0 END AS is_exit
  FROM session_pages sp
  JOIN last_page_per_session lp
    ON sp.user_pseudo_id = lp.user_pseudo_id
    AND sp.ga_session_id = lp.ga_session_id
  WHERE sp.page_location LIKE '%/products/%'
)
SELECT
  page_location,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS total_sessions,
  SUM(is_exit) AS exit_sessions,
  ROUND(SUM(is_exit) / COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) * 100, 1) AS exit_rate
FROM product_page_views
GROUP BY page_location
HAVING total_sessions >= 10
ORDER BY exit_rate DESC;
