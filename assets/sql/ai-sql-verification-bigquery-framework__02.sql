-- 出典: AIが生成したSQLは本当に正しいのか？BigQueryでの検証フレームワークを作った
-- 記事: articles/ai-sql-verification-bigquery-framework.md（AIがよく間違えるGA4 SQLのパターン）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- OK: UNNEST経由で正しく取得する
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  COUNT(*) AS event_count
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
GROUP BY 1, 2
