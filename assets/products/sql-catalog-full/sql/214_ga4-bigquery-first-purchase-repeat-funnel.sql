-- 214. GA4×BigQueryで初回購入→リピートまでのファネルを可視化する（Step 4：ファネル形式で可視化用データを作成する）
-- 用途: Step 4：ファネル形式で可視化用データを作成する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.transaction_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
),

numbered AS (
  SELECT
    user_pseudo_id,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id
      ORDER BY purchase_date, transaction_id
    ) AS purchase_number
  FROM purchases
),

funnel AS (
  SELECT
    purchase_number,
    COUNT(DISTINCT user_pseudo_id) AS users
  FROM numbered
  WHERE purchase_number <= 5
  GROUP BY purchase_number
)

SELECT
  purchase_number,
  users,
  FIRST_VALUE(users) OVER (ORDER BY purchase_number) AS first_purchase_users,
  ROUND(users / FIRST_VALUE(users) OVER (ORDER BY purchase_number) * 100, 1) AS retention_pct,
  ROUND(users / LAG(users) OVER (ORDER BY purchase_number) * 100, 1) AS step_conversion_pct
FROM funnel
ORDER BY purchase_number;
