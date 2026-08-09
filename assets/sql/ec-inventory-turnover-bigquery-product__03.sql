-- 出典: ECの在庫回転率をGA4×BigQueryで商品別に可視化して死に筋を特定する
-- 記事: articles/ec-inventory-turnover-bigquery-product.md（流入チャネル別に死に筋を掘り下げる）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 流入チャネル × 商品別 販売数量の集計
SELECT
  collected_traffic_source.manual_medium   AS medium,
  collected_traffic_source.manual_source   AS source,
  item.item_id                             AS product_id,
  item.item_name                           AS product_name,
  SUM(item.quantity)                       AS total_quantity_sold
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
  AND item.quantity > 0
GROUP BY
  medium,
  source,
  product_id,
  product_name
ORDER BY
  product_id,
  total_quantity_sold DESC
;
