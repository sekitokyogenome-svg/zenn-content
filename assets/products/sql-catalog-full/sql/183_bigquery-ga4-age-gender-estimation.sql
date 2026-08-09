-- 183. BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した（Step 4: 年齢層別の購入単価・頻度分析）
-- 用途: Step 4: 年齢層別の購入単価・頻度分析
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH user_demo AS (
  SELECT
    user_pseudo_id,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'age')) AS age_bracket
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  GROUP BY user_pseudo_id
),
user_purchases AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count,
    SUM(ecommerce.purchase_revenue) AS total_revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)
SELECT
  ud.age_bracket,
  COUNT(DISTINCT up.user_pseudo_id) AS purchasers,
  ROUND(AVG(up.total_revenue), 0) AS avg_ltv,
  ROUND(AVG(up.purchase_count), 2) AS avg_frequency,
  ROUND(AVG(up.total_revenue / up.purchase_count), 0) AS avg_order_value
FROM user_purchases up
INNER JOIN user_demo ud
  ON up.user_pseudo_id = ud.user_pseudo_id
WHERE ud.age_bracket IS NOT NULL
GROUP BY ud.age_bracket
ORDER BY avg_ltv DESC
