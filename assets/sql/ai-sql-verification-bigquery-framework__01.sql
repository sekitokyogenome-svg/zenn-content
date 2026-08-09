-- 出典: AIが生成したSQLは本当に正しいのか？BigQueryでの検証フレームワークを作った
-- 記事: articles/ai-sql-verification-bigquery-framework.md（AIがよく間違えるGA4 SQLのパターン）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- NG: ga_session_idを直接参照している（エラーになる）
SELECT
  user_pseudo_id,
  ga_session_id,
  COUNT(*) AS event_count
FROM `${PROJECT}.${DATASET}.events_*`
GROUP BY 1, 2
