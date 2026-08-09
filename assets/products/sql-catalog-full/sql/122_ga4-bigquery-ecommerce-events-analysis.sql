-- 122. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（purchaseイベントから商品別売上を抽出するSQL） その2
-- 用途: purchaseイベントから商品別売上を抽出するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
