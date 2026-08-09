-- 出典: BigQueryでGA4の生データ構造を理解する【eventsテーブル解説】
-- 記事: articles/ga4-bigquery-events-table-raw-data-structure.md（user_propertiesの展開）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  user_pseudo_id,
  (SELECT value.string_value
   FROM UNNEST(user_properties)
   WHERE key = 'membership_level') AS membership_level
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
