-- 213. GA4×BigQueryで初回購入→リピートまでのファネルを可視化する（Step 3：月次コホート別リピート率を算出する）
-- 用途: Step 3：月次コホート別リピート率を算出する
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

first_purchase AS (
  SELECT
    user_pseudo_id,
    MIN(purchase_date) AS first_purchase_date
  FROM purchases
  GROUP BY user_pseudo_id
),

cohort_repeat AS (
  SELECT
    fp.user_pseudo_id,
    FORMAT_DATE('%Y-%m', fp.first_purchase_date) AS cohort_month,
    fp.first_purchase_date,
    MIN(
      CASE WHEN p.purchase_date > fp.first_purchase_date
      THEN p.purchase_date END
    ) AS second_purchase_date
  FROM first_purchase fp
  LEFT JOIN purchases p
    ON fp.user_pseudo_id = p.user_pseudo_id
  GROUP BY fp.user_pseudo_id, fp.first_purchase_date
)

SELECT
  cohort_month,
  COUNT(*) AS first_time_buyers,
  COUNTIF(second_purchase_date IS NOT NULL) AS repeat_buyers,
  COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 30) AS repeat_within_30d,
  COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 60) AS repeat_within_60d,
  COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 90) AS repeat_within_90d,
  ROUND(COUNTIF(second_purchase_date IS NOT NULL) / COUNT(*) * 100, 1) AS repeat_rate_pct,
  ROUND(COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 30) / COUNT(*) * 100, 1) AS repeat_30d_pct,
  ROUND(COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 60) / COUNT(*) * 100, 1) AS repeat_60d_pct,
  ROUND(COUNTIF(DATE_DIFF(second_purchase_date, first_purchase_date, DAY) <= 90) / COUNT(*) * 100, 1) AS repeat_90d_pct
FROM cohort_repeat
GROUP BY cohort_month
ORDER BY cohort_month;
