-- 227. EC商品ページの離脱率をGA4×BigQueryで分析して改善につなげた事例（改善施策の前後比較SQL）
-- 用途: 改善施策の前後比較SQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH product_exit_data AS (
  -- 前述のproduct_page_viewsと同様のロジック
  -- _TABLE_SUFFIXを広めに取る（施策前後をカバーする期間）
  SELECT
    page_location,
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    is_exit,
    user_pseudo_id,
    ga_session_id
  FROM product_page_views_with_date
)
SELECT
  page_location,
  CASE
    WHEN event_date < '2026-03-15' THEN 'before'
    ELSE 'after'
  END AS period,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
  SUM(is_exit) AS exits,
  ROUND(SUM(is_exit) / COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) * 100, 1) AS exit_rate
FROM product_exit_data
WHERE page_location = '/products/target-product'
GROUP BY page_location, period
ORDER BY period;
