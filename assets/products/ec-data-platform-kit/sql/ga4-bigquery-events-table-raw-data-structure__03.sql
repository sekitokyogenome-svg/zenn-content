-- BigQueryでGA4の生データ構造を理解する【eventsテーブル解説】
-- 用途: itemsの展開（eコマースの場合）
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
