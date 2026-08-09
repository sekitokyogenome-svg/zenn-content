-- 出典: GA4イベントパラメータをUNNESTで展開するSQLパターン集
-- 記事: articles/ga4-bigquery-unnest-sql-patterns.md（パターン4：CROSS JOINでitemを展開する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
