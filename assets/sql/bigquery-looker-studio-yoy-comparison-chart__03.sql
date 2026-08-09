-- 出典: BigQuery × Looker Studioで前年同期比グラフを作る方法
-- 記事: articles/bigquery-looker-studio-yoy-comparison-chart.md（パターン3: スコアカードで前年比を大きく表示）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) THEN revenue END) AS revenue_ytd,
  SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) - 1 THEN revenue END) AS revenue_ytd_ly,
  SAFE_DIVIDE(
    SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) THEN revenue END)
    - SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) - 1 THEN revenue END),
    SUM(CASE WHEN year = EXTRACT(YEAR FROM CURRENT_DATE()) - 1 THEN revenue END)
  ) * 100 AS ytd_yoy_pct
FROM monthly_data
WHERE month_num <= EXTRACT(MONTH FROM CURRENT_DATE())
