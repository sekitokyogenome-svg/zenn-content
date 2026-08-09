-- 283. EC事業の粗利率をBigQueryで商品×チャネル別に自動計算する仕組み（商品×チャネル別の粗利率を計算するSQL）
-- 用途: 商品×チャネル別の粗利率を計算するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_purchase AS (
  -- （前述のクエリをCTEとして再利用）
  SELECT
    medium,
    source,
    transaction_id,
    revenue,
    event_date
  FROM /* 上記のSQLをここにネスト、またはビューとして呼び出す */
    `your_project.analytics.session_purchase_view`
),

item_margin AS (
  SELECT
    oi.order_id,
    oi.item_sku,
    oi.item_name,
    SUM(oi.quantity * oi.unit_price) AS item_revenue,
    SUM(oi.quantity * oi.unit_cost)  AS item_cost,
    SUM(oi.quantity * (oi.unit_price - oi.unit_cost)) AS gross_profit
  FROM
    `your_project.sales.order_items` AS oi
  GROUP BY
    oi.order_id, oi.item_sku, oi.item_name
)

SELECT
  sp.medium,
  sp.source,
  CONCAT(sp.medium, ' / ', COALESCE(sp.source, '(not set)')) AS channel,
  im.item_sku,
  im.item_name,
  SUM(im.item_revenue)  AS total_revenue,
  SUM(im.item_cost)     AS total_cost,
  SUM(im.gross_profit)  AS total_gross_profit,
  ROUND(
    SAFE_DIVIDE(SUM(im.gross_profit), SUM(im.item_revenue)) * 100,
    2
  ) AS gross_margin_rate
FROM
  item_margin AS im
LEFT JOIN
  session_purchase AS sp
  ON im.order_id = sp.transaction_id
GROUP BY
  sp.medium, sp.source, channel, im.item_sku, im.item_name
ORDER BY
  total_gross_profit DESC
