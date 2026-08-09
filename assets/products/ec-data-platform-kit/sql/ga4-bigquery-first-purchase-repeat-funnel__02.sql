-- GA4×BigQueryで初回購入→リピートまでのファネルを可視化する
-- 用途: Step 2：2回目・3回目の購入と購入間隔を算出する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください
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
    purchase_date,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id
      ORDER BY purchase_date, transaction_id
    ) AS purchase_number
  FROM purchases
),

with_intervals AS (
  SELECT
    user_pseudo_id,
    purchase_number,
    purchase_date,
    LAG(purchase_date) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY purchase_number
    ) AS prev_purchase_date,
    DATE_DIFF(
      purchase_date,
      LAG(purchase_date) OVER (
        PARTITION BY user_pseudo_id
        ORDER BY purchase_number
      ),
      DAY
    ) AS days_since_prev_purchase
  FROM numbered
)

SELECT
  purchase_number,
  COUNT(*) AS user_count,
  ROUND(AVG(days_since_prev_purchase), 1) AS avg_days_between,
  APPROX_QUANTILES(days_since_prev_purchase, 2)[OFFSET(1)] AS median_days_between
FROM with_intervals
GROUP BY purchase_number
ORDER BY purchase_number;
