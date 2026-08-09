-- GA4×BigQueryでポイント還元施策の効果をコホート分析で検証した
-- 用途: Step 4: 施策のROI算出
-- 必要テーブル: (なし)
-- コスト: `SELECT *` を含みます。必要な列だけに絞るとコストが下がります
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
