-- 出典: GA4×BigQueryでEC定期購入の継続率を分析する
-- 記事: articles/ga4-bigquery-subscription-retention.md（Step 3: チャーン率（解約率）の算出）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH retention_data AS (
  -- 上記Step 2のクエリをサブクエリとして利用
  -- ここでは簡略化のためWITH句で結果を受ける想定
  SELECT
    cohort_month,
    months_since_first,
    retention_pct
  FROM (
    -- Step 2のクエリ結果
  )
),
churn_calc AS (
  SELECT
    cohort_month,
    months_since_first,
    retention_pct,
    LAG(retention_pct) OVER (
      PARTITION BY cohort_month
      ORDER BY months_since_first
    ) AS prev_retention_pct
  FROM retention_data
)
SELECT
  cohort_month,
  months_since_first,
  retention_pct,
  ROUND(prev_retention_pct - retention_pct, 1) AS monthly_churn_pct
FROM churn_calc
WHERE months_since_first > 0
ORDER BY cohort_month, months_since_first
