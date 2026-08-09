-- 164. Claude Codeで売上が下がった原因をBigQueryから自動で仮説生成させる
-- 用途: Step 1：売上変化の検出
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH current_period AS (
  SELECT SUM(total_revenue) AS revenue
  FROM `${PROJECT}.${DATASET}.mart_channel_performance`
  WHERE date BETWEEN DATE_TRUNC(CURRENT_DATE(), MONTH)
    AND CURRENT_DATE()
),
previous_period AS (
  SELECT SUM(total_revenue) AS revenue
  FROM `${PROJECT}.${DATASET}.mart_channel_performance`
  WHERE date BETWEEN DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH)
    AND LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH))
)
SELECT
  c.revenue AS current_revenue,
  p.revenue AS previous_revenue,
  c.revenue - p.revenue AS diff,
  ROUND((c.revenue - p.revenue) / p.revenue * 100, 1) AS change_pct
FROM current_period c, previous_period p
