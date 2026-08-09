-- GA4×BigQueryで初回購入→リピートまでのファネルを可視化する
-- 用途: Step 1：ユーザーごとの初回購入日を特定する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH purchases AS (
  SELECT
    user_pseudo_id,
    PARSE_DATE('%Y%m%d', event_date) AS purchase_date,
    ecommerce.transaction_id,
    ecommerce.purchase_revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
),

user_purchases AS (
  SELECT
    user_pseudo_id,
    purchase_date,
    transaction_id,
    purchase_revenue,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id
      ORDER BY purchase_date, transaction_id
    ) AS purchase_number,
    MIN(purchase_date) OVER (
      PARTITION BY user_pseudo_id
    ) AS first_purchase_date
  FROM purchases
)

SELECT * FROM user_purchases
ORDER BY user_pseudo_id, purchase_number;
