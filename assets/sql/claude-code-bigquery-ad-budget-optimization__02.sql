-- 出典: Claude Code × BigQueryでEC広告の予算配分を自動最適化する提案ツールを作った
-- 記事: articles/claude-code-bigquery-ad-budget-optimization.md（広告コストデータを結合する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 広告コストテーブルの例
CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.ad_costs` (
  month STRING,
  channel STRING,
  cost FLOAT64
);

-- ROAS算出クエリ
WITH revenue AS (
  -- 上記の channel_revenue CTEと同じ
),
costs AS (
  SELECT channel, cost
  FROM `${PROJECT}.${DATASET}.ad_costs`
  WHERE month = FORMAT_DATE(
    '%Y-%m', DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH))
)
SELECT
  r.channel,
  r.sessions,
  r.conversions,
  r.revenue,
  c.cost AS ad_cost,
  SAFE_DIVIDE(r.revenue, c.cost) * 100 AS roas_pct,
  SAFE_DIVIDE(c.cost, r.conversions) AS cpa
FROM revenue r
LEFT JOIN costs c ON r.channel = c.channel
WHERE c.cost > 0
ORDER BY roas_pct DESC;
