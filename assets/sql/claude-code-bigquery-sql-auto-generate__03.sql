-- 出典: Claude CodeでBigQueryのSQLを自然言語から自動生成する
-- 記事: articles/claude-code-bigquery-sql-auto-generate.md（LIMIT句で結果を確認）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 生成されたクエリの末尾に LIMIT を足して少量で確認する
SELECT
  event_date,
  event_name,
  user_pseudo_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX = '20260301'
LIMIT 10
