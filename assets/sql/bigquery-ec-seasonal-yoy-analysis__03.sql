-- 出典: ECの季節変動をBigQueryで前年比分析して仕入れ計画に活かす方法
-- 記事: articles/bigquery-ec-seasonal-yoy-analysis.md（商品カテゴリ別×月別の分析）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH category_monthly AS (
  SELECT
    EXTRACT(YEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS year,
    EXTRACT(MONTH FROM PARSE_DATE('%Y%m%d', event_date)) AS month,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS category,
    SUM(ecommerce.purchase_revenue) AS revenue,
    SUM(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'quantity')
    ) AS quantity
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND ecommerce.purchase_revenue > 0
    AND _TABLE_SUFFIX BETWEEN '20250101' AND '20260331'
  GROUP BY year, month, category
)
SELECT
  curr.category,
  curr.month,
  curr.revenue AS current_revenue,
  prev.revenue AS prev_revenue,
  ROUND(SAFE_DIVIDE(curr.revenue - prev.revenue, prev.revenue) * 100, 1) AS revenue_yoy_pct,
  curr.quantity AS current_qty,
  prev.quantity AS prev_qty
FROM category_monthly curr
LEFT JOIN category_monthly prev
  ON curr.category = prev.category
  AND curr.month = prev.month
  AND curr.year = prev.year + 1
WHERE curr.year = 2026
ORDER BY curr.category, curr.month;
