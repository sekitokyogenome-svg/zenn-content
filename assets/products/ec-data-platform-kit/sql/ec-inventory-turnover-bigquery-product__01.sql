-- ECの在庫回転率をGA4×BigQueryで商品別に可視化して死に筋を特定する
-- 用途: GA4のBigQueryエクスポートから商品別販売数量を取得するSQL
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
