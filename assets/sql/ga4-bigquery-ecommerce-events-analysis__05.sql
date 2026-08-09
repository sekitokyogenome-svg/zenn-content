-- 出典: BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】
-- 記事: articles/ga4-bigquery-ecommerce-events-analysis.md（カテゴリ別・商品別の売上集計）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- カテゴリ別売上
SELECT
  item.item_category,
  COUNT(DISTINCT ecommerce.transaction_id) AS transactions,
  SUM(item.quantity) AS total_quantity,
  ROUND(SUM(item.item_revenue), 0) AS total_revenue,
  ROUND(SAFE_DIVIDE(SUM(item.item_revenue), SUM(item.quantity)), 0) AS avg_unit_price
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
  AND event_name = 'purchase'
  AND item.item_category IS NOT NULL
GROUP BY
  item.item_category
ORDER BY
  total_revenue DESC
