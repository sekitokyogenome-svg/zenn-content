-- 出典: BigQueryで売上上位20%の商品が生み出す収益構造をパレート分析した
-- 記事: articles/bigquery-ec-pareto-top20-revenue.md（Step 3: ABC分析のサマリー）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH item_revenue AS (
  SELECT
    items.item_name,
    SUM(items.item_revenue) AS total_revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS items
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
    AND items.item_revenue > 0
  GROUP BY items.item_name
),
ranked AS (
  SELECT
    item_name,
    total_revenue,
    ROW_NUMBER() OVER (ORDER BY total_revenue DESC) AS rank,
    COUNT(*) OVER () AS total_items,
    SUM(total_revenue) OVER () AS grand_total
  FROM item_revenue
),
classified AS (
  SELECT
    *,
    ROUND(SUM(total_revenue) OVER (ORDER BY rank) / grand_total * 100, 2) AS cum_pct,
    CASE
      WHEN ROUND(SUM(total_revenue) OVER (ORDER BY rank) / grand_total * 100, 2) <= 80 THEN 'A'
      WHEN ROUND(SUM(total_revenue) OVER (ORDER BY rank) / grand_total * 100, 2) <= 95 THEN 'B'
      ELSE 'C'
    END AS abc_rank
  FROM ranked
)
SELECT
  abc_rank,
  COUNT(*) AS item_count,
  ROUND(COUNT(*) / MAX(total_items) * 100, 1) AS item_pct,
  SUM(total_revenue) AS total_revenue,
  ROUND(SUM(total_revenue) / MAX(grand_total) * 100, 1) AS revenue_pct
FROM classified
GROUP BY abc_rank
ORDER BY abc_rank
