-- 出典: GA4×BigQueryでカート放棄率を正確に計測・改善する方法
-- 記事: articles/ga4-bigquery-cart-abandonment-rate.md（商品別のカゴ落ち分析）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH cart_items AS (
  SELECT
    user_pseudo_id,
    item.item_id,
    item.item_name
  FROM `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS item
  WHERE event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchased_items AS (
  SELECT
    user_pseudo_id,
    item.item_id
  FROM `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS item
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  c.item_id,
  c.item_name,
  COUNT(DISTINCT c.user_pseudo_id) AS cart_users,
  COUNT(DISTINCT p.user_pseudo_id) AS purchase_users,
  COUNT(DISTINCT c.user_pseudo_id) - COUNT(DISTINCT p.user_pseudo_id) AS abandoned_users,
  ROUND(
    (COUNT(DISTINCT c.user_pseudo_id) - COUNT(DISTINCT p.user_pseudo_id))
    / COUNT(DISTINCT c.user_pseudo_id) * 100, 1
  ) AS abandonment_rate
FROM cart_items c
LEFT JOIN purchased_items p
  ON c.user_pseudo_id = p.user_pseudo_id
  AND c.item_id = p.item_id
GROUP BY c.item_id, c.item_name
HAVING COUNT(DISTINCT c.user_pseudo_id) >= 5
ORDER BY abandoned_users DESC
LIMIT 20;
