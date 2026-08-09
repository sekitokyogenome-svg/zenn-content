-- 出典: GA4×BigQueryでポイント還元施策の効果をコホート分析で検証した
-- 記事: articles/ga4-bigquery-point-reward-cohort.md（Step 2: コホート別の月次購入回数）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
    _TABLE_SUFFIX BETWEEN '20250301' AND '20250430'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),
subsequent_purchases AS (
  SELECT
    e.user_pseudo_id,
    fp.cohort_month,
    DATE_DIFF(
      DATE(TIMESTAMP_MICROS(e.event_timestamp), 'Asia/Tokyo'),
      fp.first_purchase_date,
      MONTH
    ) AS months_after
  FROM
    `${PROJECT}.${DATASET}.events_*` e
  INNER JOIN first_purchase fp
    ON e.user_pseudo_id = fp.user_pseudo_id
  WHERE
    e._TABLE_SUFFIX BETWEEN '20250301' AND '20251231'
    AND e.event_name = 'purchase'
    AND fp.cohort_month IN ('2025-03', '2025-04')
)
SELECT
  cohort_month,
  CASE
    WHEN cohort_month = '2025-03' THEN '施策前'
    WHEN cohort_month = '2025-04' THEN '施策後'
  END AS cohort_label,
  months_after,
  COUNT(DISTINCT user_pseudo_id) AS active_users,
  COUNT(*) AS total_purchases
FROM subsequent_purchases
WHERE months_after BETWEEN 0 AND 6
GROUP BY cohort_month, cohort_label, months_after
ORDER BY cohort_month, months_after
