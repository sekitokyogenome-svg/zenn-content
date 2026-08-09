-- 272. ECの在庫回転率をGA4×BigQueryで商品別に可視化して死に筋を特定する（在庫マスタと結合して回転率を算出するSQL）
-- 用途: 在庫マスタと結合して回転率を算出するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH sales AS (
  SELECT
    item.item_id                     AS product_id,
    SUM(item.quantity)               AS total_quantity_sold
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS item
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND event_name = 'purchase'
    AND item.quantity > 0
  GROUP BY
    product_id
),
inventory AS (
  SELECT
    product_id,
    product_name,
    stock_start,
    stock_end,
    SAFE_DIVIDE(stock_start + stock_end, 2) AS avg_stock
  FROM
    `${PROJECT}.${DATASET}.inventory_master`
)
SELECT
  inv.product_id,
  inv.product_name,
  COALESCE(s.total_quantity_sold, 0)              AS total_quantity_sold,
  inv.avg_stock,
  ROUND(
    SAFE_DIVIDE(COALESCE(s.total_quantity_sold, 0), inv.avg_stock),
    2
  )                                               AS inventory_turnover_rate
FROM
  inventory AS inv
LEFT JOIN
  sales AS s
  ON inv.product_id = s.product_id
ORDER BY
  inventory_turnover_rate ASC  -- 回転率の低い順（死に筋候補が上位に）
;
