-- 出典: ECの在庫回転率をGA4×BigQueryで商品別に可視化して死に筋を特定する
-- 記事: articles/ec-inventory-turnover-bigquery-product.md（GA4のBigQueryエクスポートから商品別販売数量を取得するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 商品別 販売数量・売上金額の集計（GA4 BigQueryエクスポート）
SELECT
  item.item_id                          AS product_id,
  item.item_name                        AS product_name,
  SUM(item.quantity)                    AS total_quantity_sold,
  ROUND(SUM(item.item_revenue), 2)      AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS item
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
  AND item.quantity > 0
GROUP BY
  product_id,
  product_name
ORDER BY
  total_quantity_sold DESC
;
