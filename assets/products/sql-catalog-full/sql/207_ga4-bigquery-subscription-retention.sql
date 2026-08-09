-- 207. GA4×BigQueryでEC定期購入の継続率を分析する（Step 2: 月別継続率の算出）
-- 用途: Step 2: 月別継続率の算出
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH first_purchase AS (
  SELECT
    user_pseudo_id,
    DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo') AS first_purchase_date,
    FORMAT_DATE('%Y-%m',
      DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo')
    ) AS cohort_month
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),
monthly_purchases AS (
  SELECT
    user_pseudo_id,
    FORMAT_DATE('%Y-%m',
      DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')
    ) AS purchase_month
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id, purchase_month
),
cohort_activity AS (
  SELECT
    fp.cohort_month,
    DATE_DIFF(
      PARSE_DATE('%Y-%m', mp.purchase_month),
      PARSE_DATE('%Y-%m', fp.cohort_month),
      MONTH
    ) AS months_since_first,
    COUNT(DISTINCT fp.user_pseudo_id) AS active_users
  FROM first_purchase fp
  INNER JOIN monthly_purchases mp
    ON fp.user_pseudo_id = mp.user_pseudo_id
  GROUP BY fp.cohort_month, months_since_first
),
cohort_size AS (
  SELECT
    cohort_month,
    COUNT(*) AS total_users
  FROM first_purchase
  GROUP BY cohort_month
)
SELECT
  ca.cohort_month,
  ca.months_since_first,
  cs.total_users,
  ca.active_users,
  ROUND(ca.active_users / cs.total_users * 100, 1) AS retention_pct
FROM cohort_activity ca
INNER JOIN cohort_size cs
  ON ca.cohort_month = cs.cohort_month
WHERE ca.months_since_first BETWEEN 0 AND 12
ORDER BY ca.cohort_month, ca.months_since_first
