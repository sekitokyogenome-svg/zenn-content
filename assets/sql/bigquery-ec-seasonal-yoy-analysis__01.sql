-- 出典: ECの季節変動をBigQueryで前年比分析して仕入れ計画に活かす方法
-- 記事: articles/bigquery-ec-seasonal-yoy-analysis.md（月別売上の前年比SQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH monthly_revenue AS (
  SELECT
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS year_month,
    EXTRACT(YEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS year,
    EXTRACT(MONTH FROM PARSE_DATE('%Y%m%d', event_date)) AS month,
    SUM(ecommerce.purchase_revenue) AS revenue,
    COUNT(DISTINCT user_pseudo_id) AS purchasers
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND ecommerce.purchase_revenue > 0
    AND _TABLE_SUFFIX BETWEEN '20250101' AND '20260331'
  GROUP BY year_month, year, month
)
SELECT
  curr.month,
  curr.year_month AS current_period,
  curr.revenue AS current_revenue,
  prev.revenue AS prev_revenue,
  curr.purchasers AS current_purchasers,
  prev.purchasers AS prev_purchasers,
  ROUND(SAFE_DIVIDE(curr.revenue - prev.revenue, prev.revenue) * 100, 1) AS revenue_yoy_pct,
  ROUND(SAFE_DIVIDE(curr.purchasers - prev.purchasers, prev.purchasers) * 100, 1) AS purchasers_yoy_pct
FROM monthly_revenue curr
LEFT JOIN monthly_revenue prev
  ON curr.month = prev.month
  AND curr.year = prev.year + 1
WHERE curr.year = 2026
ORDER BY curr.month;
