-- 出典: GA4×BigQueryでポイント還元施策の効果をコホート分析で検証した
-- 記事: articles/ga4-bigquery-point-reward-cohort.md（Step 4: 施策のROI算出）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 施策コストと効果のサマリー（手動入力値との組み合わせ）
WITH cohort_metrics AS (
  -- Step 3の結果を仮定
  SELECT '施策前' AS label, 150 AS customers, 12500 AS avg_ltv UNION ALL
  SELECT '施策後' AS label, 220 AS customers, 11800 AS avg_ltv
)
SELECT
  *,
  customers * avg_ltv AS total_ltv,
  CASE
    WHEN label = '施策後' THEN customers * 500  -- ポイント還元500円/人
    ELSE 0
  END AS campaign_cost,
  CASE
    WHEN label = '施策後' THEN (customers * avg_ltv) - (customers * 500)
    ELSE customers * avg_ltv
  END AS net_revenue
FROM cohort_metrics
