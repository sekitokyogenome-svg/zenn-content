-- 230. GA4×BigQueryでEC定期購入の継続率を分析する（Step 1: 初回購入月の特定）
-- 用途: Step 1: 初回購入月の特定
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH first_purchase AS (
  SELECT
    user_pseudo_id,
    FORMAT_DATE('%Y-%m',
      DATE(TIMESTAMP_MICROS(MIN(event_timestamp)), 'Asia/Tokyo')
    ) AS cohort_month
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)
SELECT
  cohort_month,
  COUNT(*) AS new_subscribers
FROM first_purchase
GROUP BY cohort_month
ORDER BY cohort_month
