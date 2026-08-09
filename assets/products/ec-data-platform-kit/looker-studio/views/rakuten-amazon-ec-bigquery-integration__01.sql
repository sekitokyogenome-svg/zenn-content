-- 楽天・Amazon・自社ECの売上データをBigQueryに集約して一元管理する方法
-- 出典: articles/rakuten-amazon-ec-bigquery-integration.md

CREATE OR REPLACE VIEW `your_project.ec_dataset.unified_sales` AS

-- 楽天市場の売上データ
SELECT
  '楽天市場'                              AS channel,
  PARSE_DATE('%Y%m%d', order_date_str)   AS order_date,
  order_id,
  item_id                                 AS product_id,
  item_name                               AS product_name,
  unit_price                              AS price,
  quantity,
  unit_price * quantity                   AS revenue,
  shipping_fee,
  status
FROM `your_project.ec_dataset.rakuten_orders`

UNION ALL

-- Amazon の売上データ
SELECT
  'Amazon'                                AS channel,
  DATE(purchase_date)                     AS order_date,
  amazon_order_id                         AS order_id,
  asin                                    AS product_id,
  product_name,
  item_price                              AS price,
  quantity_ordered                        AS quantity,
  item_price * quantity_ordered           AS revenue,
  shipping_price                          AS shipping_fee,
  order_status                            AS status
FROM `your_project.ec_dataset.amazon_orders`

UNION ALL

-- 自社ECの売上データ
SELECT
  '自社EC'                                AS channel,
  DATE(created_at)                        AS order_date,
  CAST(id AS STRING)                      AS order_id,
  sku                                     AS product_id,
  product_name,
  price,
  quantity,
  price * quantity                        AS revenue,
  shipping_amount                         AS shipping_fee,
  order_status                            AS status
FROM `your_project.ec_dataset.mysite_orders`;
