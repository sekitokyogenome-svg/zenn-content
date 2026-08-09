-- 出典: BigQueryでGA4の生データ構造を理解する【eventsテーブル解説】
-- 記事: articles/ga4-bigquery-events-table-raw-data-structure.md（日付フィルタの書き方）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 2026年3月のデータだけをスキャン
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
