-- 65. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（add_to_cart分析：カートに入れたが購入されなかった商品）
-- 用途: add_to_cart分析：カートに入れたが購入されなかった商品
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH cart_items AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    item.item_id,
    item.item_name
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS item
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
    AND event_name = 'add_to_cart'
),

purchased_items AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    item.item_id
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS item
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
    AND event_name = 'purchase'
)

SELECT
  c.item_id,
  c.item_name,
  COUNT(*) AS cart_add_count,
  COUNTIF(p.item_id IS NOT NULL) AS purchase_count,
  COUNTIF(p.item_id IS NULL) AS abandoned_count,
  ROUND(
    SAFE_DIVIDE(COUNTIF(p.item_id IS NULL), COUNT(*)) * 100, 1
  ) AS abandonment_rate
FROM
  cart_items c
LEFT JOIN
  purchased_items p
  ON c.user_pseudo_id = p.user_pseudo_id
  AND c.ga_session_id = p.ga_session_id
  AND c.item_id = p.item_id
GROUP BY
  c.item_id, c.item_name
ORDER BY
  abandoned_count DESC
