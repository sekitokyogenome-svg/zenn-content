-- 出典: GA4イベントパラメータをUNNESTで展開するSQLパターン集
-- 記事: articles/ga4-bigquery-unnest-sql-patterns.md（パターン3：セッションIDを構築する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  CONCAT(
    user_pseudo_id,
    '-',
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  event_date,
  event_name
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
