-- 出典: BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】
-- 記事: articles/ga4-bigquery-ecommerce-events-analysis.md（purchaseイベントから商品別売上を抽出するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  user_pseudo_id,
  ecommerce.transaction_id,
  item.item_name,
  item.item_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
  AND event_name = 'purchase'
