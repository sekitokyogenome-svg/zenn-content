-- 88. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（purchaseイベントから商品別売上を抽出するSQL） その1
-- 用途: purchaseイベントから商品別売上を抽出するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
