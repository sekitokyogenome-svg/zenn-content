-- 出典: GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する
-- 記事: articles/ga4-bigquery-cac-by-channel.md（CACの評価基準）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH customer_ltv AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count,
    SUM(ecommerce.purchase_revenue) AS total_revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)

SELECT
  ROUND(AVG(total_revenue), 0) AS avg_ltv,
  ROUND(PERCENTILE_CONT(total_revenue, 0.5) OVER(), 0) AS median_ltv,
  ROUND(AVG(purchase_count), 1) AS avg_purchase_count
FROM customer_ltv
LIMIT 1
