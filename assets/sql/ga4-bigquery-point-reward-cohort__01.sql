-- 出典: GA4×BigQueryでポイント還元施策の効果をコホート分析で検証した
-- 記事: articles/ga4-bigquery-point-reward-cohort.md（Step 1: コホートの抽出）
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
)
SELECT
  cohort_month,
  CASE
    WHEN cohort_month = '2025-03' THEN '施策前'
    WHEN cohort_month = '2025-04' THEN '施策後'
  END AS cohort_label,
  COUNT(*) AS new_customers
FROM first_purchase
WHERE cohort_month IN ('2025-03', '2025-04')
GROUP BY cohort_month, cohort_label
ORDER BY cohort_month
