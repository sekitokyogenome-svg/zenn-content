-- 190. GA4×BigQueryでカート放棄率を正確に計測・改善する方法（デバイス別のカート放棄率）
-- 用途: デバイス別のカート放棄率
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH add_to_cart_users AS (
  SELECT DISTINCT
    user_pseudo_id,
    device.category AS device_category
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchase_users AS (
  SELECT DISTINCT user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  a.device_category,
  COUNT(*) AS total_add_to_cart_users,
  COUNTIF(p.user_pseudo_id IS NULL) AS abandoned_users,
  ROUND(
    COUNTIF(p.user_pseudo_id IS NULL) / COUNT(*) * 100, 1
  ) AS cart_abandonment_rate
FROM add_to_cart_users a
LEFT JOIN purchase_users p
  ON a.user_pseudo_id = p.user_pseudo_id
GROUP BY a.device_category
ORDER BY cart_abandonment_rate DESC;
