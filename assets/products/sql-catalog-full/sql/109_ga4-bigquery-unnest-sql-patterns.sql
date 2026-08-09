-- 109. GA4イベントパラメータをUNNESTで展開するSQLパターン集（パターン4：CROSS JOINでitemを展開する）
-- 用途: パターン4：CROSS JOINでitemを展開する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_date,
  user_pseudo_id,
  item.item_id,
  item.item_name,
  item.item_category,
  item.price,
  item.quantity
FROM `${PROJECT}.${DATASET}.events_*`
CROSS JOIN UNNEST(items) AS item
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'purchase'
