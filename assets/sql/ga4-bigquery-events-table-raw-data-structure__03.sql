-- 出典: BigQueryでGA4の生データ構造を理解する【eventsテーブル解説】
-- 記事: articles/ga4-bigquery-events-table-raw-data-structure.md（itemsの展開（eコマースの場合））
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  event_date,
  user_pseudo_id,
  items.item_id,
  items.item_name,
  items.item_category,
  items.price,
  items.quantity
FROM `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS items
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'purchase'
