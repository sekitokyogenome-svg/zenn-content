-- 151. Claude Code × Python × BigQueryでLTV予測モデルを作った（RFM（Recency, Frequency, Monetary）データの取得SQL）
-- 用途: RFM（Recency, Frequency, Monetary）データの取得SQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.purchase_revenue AS revenue,
    ecommerce.transaction_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
    AND _TABLE_SUFFIX BETWEEN '20250101' AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),
user_metrics AS (
  SELECT
    user_pseudo_id,
    MIN(purchase_date) AS first_purchase,
    MAX(purchase_date) AS last_purchase,
    COUNT(DISTINCT transaction_id) AS frequency,
    SUM(revenue) AS monetary,
    DATE_DIFF(MAX(purchase_date), MIN(purchase_date), DAY) AS recency_days,
    DATE_DIFF(CURRENT_DATE(), MIN(purchase_date), DAY) AS tenure_days
  FROM purchases
  GROUP BY user_pseudo_id
)
SELECT
  user_pseudo_id,
  frequency,
  recency_days,
  tenure_days,
  monetary,
  monetary / frequency AS avg_order_value,
  first_purchase,
  last_purchase
FROM user_metrics
WHERE frequency >= 1
ORDER BY monetary DESC
