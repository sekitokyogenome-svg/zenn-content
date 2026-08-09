-- 出典: 2024年問題に備えるデータ基盤―配送コストをBigQueryで最適化する
-- 記事: articles/logistics-2026-bigquery-shipping-cost.md（商品カテゴリ別の配送コスト分析で値付けを見直す）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 商品カテゴリ別の実質利益を計算する
SELECT
  p.category                                              AS product_category,
  COUNT(DISTINCT o.order_id)                              AS order_count,
  ROUND(SUM(o.revenue), 0)                               AS total_revenue,
  ROUND(SUM(o.cost_of_goods), 0)                         AS total_cogs,
  ROUND(SUM(s.shipping_cost), 0)                         AS total_shipping_cost,
  ROUND(SUM(o.revenue - o.cost_of_goods - s.shipping_cost), 0) AS actual_profit,
  ROUND(
    SUM(o.revenue - o.cost_of_goods - s.shipping_cost)
    / NULLIF(SUM(o.revenue), 0) * 100, 1
  )                                                       AS actual_margin_pct
FROM
  `${PROJECT}.${DATASET}.orders`          AS o
  LEFT JOIN `${PROJECT}.${DATASET}.products`       AS p
    ON o.product_id = p.product_id
  LEFT JOIN `${PROJECT}.${DATASET}.shipping_costs` AS s
    ON o.order_id = s.order_id
WHERE
  o.order_date BETWEEN '2026-01-01' AND '2026-07-31'
GROUP BY
  product_category
ORDER BY
  actual_margin_pct ASC
