-- 出典: GA4イベントパラメータをUNNESTで展開するSQLパターン集
-- 記事: articles/ga4-bigquery-unnest-sql-patterns.md（パターン4：CROSS JOINでitemを展開する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

FROM `${PROJECT}.${DATASET}.events_*`
LEFT JOIN UNNEST(items) AS item
