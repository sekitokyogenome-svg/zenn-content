-- BigQueryで売上上位20%の商品が生み出す収益構造をパレート分析した
-- 用途: Step 2: 累積比率を算出してパレート曲線を描く
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH item_revenue AS (
  SELECT
    items.item_name,
    items.item_id,
    SUM(items.item_revenue) AS total_revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS items
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
    AND items.item_revenue > 0
  GROUP BY
    items.item_name, items.item_id
),
ranked AS (
  SELECT
    item_name,
    item_id,
    total_revenue,
    ROW_NUMBER() OVER (ORDER BY total_revenue DESC) AS rank,
    COUNT(*) OVER () AS total_items,
    SUM(total_revenue) OVER () AS grand_total
  FROM item_revenue
),
cumulative AS (
  SELECT
    *,
    SUM(total_revenue) OVER (ORDER BY rank) AS cumulative_revenue,
    ROUND(rank / total_items * 100, 2) AS item_pct,
    ROUND(SUM(total_revenue) OVER (ORDER BY rank) / grand_total * 100, 2) AS cumulative_revenue_pct
  FROM ranked
)
SELECT
  rank,
  item_name,
  total_revenue,
  item_pct,
  cumulative_revenue_pct,
  CASE
    WHEN cumulative_revenue_pct <= 80 THEN 'A'
    WHEN cumulative_revenue_pct <= 95 THEN 'B'
    ELSE 'C'
  END AS abc_rank
FROM cumulative
ORDER BY rank
