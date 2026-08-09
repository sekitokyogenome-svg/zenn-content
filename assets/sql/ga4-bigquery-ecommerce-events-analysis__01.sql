-- 出典: BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】
-- 記事: articles/ga4-bigquery-ecommerce-events-analysis.md（purchaseイベントから商品別売上を抽出するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  item.item_id,
  item.item_name,
  item.item_category,
  COUNT(DISTINCT ecommerce.transaction_id) AS transaction_count,
  SUM(item.quantity) AS total_quantity,
  SUM(item.item_revenue) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
  AND event_name = 'purchase'
GROUP BY
  item.item_id, item.item_name, item.item_category
ORDER BY
  total_revenue DESC
