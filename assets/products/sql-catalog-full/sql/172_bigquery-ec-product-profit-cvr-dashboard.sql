-- 172. BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った（商品別の流入数とCVRを算出するSQL）
-- 用途: 商品別の流入数とCVRを算出するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH product_views AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_id') AS item_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_name') AS item_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'view_item'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
product_purchases AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_id') AS item_id,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
    AND ecommerce.purchase_revenue > 0
)
SELECT
  v.item_id,
  v.item_name,
  COUNT(DISTINCT CONCAT(v.user_pseudo_id, '-', CAST(v.ga_session_id AS STRING))) AS view_sessions,
  COUNT(DISTINCT CONCAT(p.user_pseudo_id, '-', CAST(p.ga_session_id AS STRING))) AS purchase_sessions,
  ROUND(
    SAFE_DIVIDE(
      COUNT(DISTINCT CONCAT(p.user_pseudo_id, '-', CAST(p.ga_session_id AS STRING))),
      COUNT(DISTINCT CONCAT(v.user_pseudo_id, '-', CAST(v.ga_session_id AS STRING)))
    ) * 100, 2
  ) AS cvr,
  SUM(p.revenue) AS total_revenue
FROM product_views v
LEFT JOIN product_purchases p
  ON v.user_pseudo_id = p.user_pseudo_id
  AND v.ga_session_id = p.ga_session_id
  AND v.item_id = p.item_id
GROUP BY v.item_id, v.item_name
HAVING view_sessions >= 10
ORDER BY total_revenue DESC;
