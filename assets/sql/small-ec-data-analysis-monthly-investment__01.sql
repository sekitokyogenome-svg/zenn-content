-- 出典: 中小EC経営者がデータ分析に月1万円投資すべき理由
-- 記事: articles/small-ec-data-analysis-monthly-investment.md（2. 離脱ポイントの特定）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- ファネル分析の例（BigQuery）
SELECT
  COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN user_pseudo_id END) AS view_item_users,
  COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN user_pseudo_id END) AS add_to_cart_users,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_pseudo_id END) AS purchase_users
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
