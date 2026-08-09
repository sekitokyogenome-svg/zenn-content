-- 出典: GA4×BigQueryでカート放棄率を正確に計測・改善する方法
-- 記事: articles/ga4-bigquery-cart-abandonment-rate.md（改善の効果を時系列で追跡する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH weekly_cart AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK) AS week_start,
    user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'add_to_cart'
    AND _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
),
weekly_purchase AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK) AS week_start,
    user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
)
SELECT
  c.week_start,
  COUNT(DISTINCT c.user_pseudo_id) AS cart_users,
  COUNT(DISTINCT p.user_pseudo_id) AS purchase_users,
  ROUND(
    (COUNT(DISTINCT c.user_pseudo_id) - COUNT(DISTINCT p.user_pseudo_id))
    / COUNT(DISTINCT c.user_pseudo_id) * 100, 1
  ) AS cart_abandonment_rate
FROM weekly_cart c
LEFT JOIN weekly_purchase p
  ON c.week_start = p.week_start
  AND c.user_pseudo_id = p.user_pseudo_id
GROUP BY c.week_start
ORDER BY c.week_start;
