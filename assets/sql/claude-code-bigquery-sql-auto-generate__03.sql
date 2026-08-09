-- 出典: Claude CodeでBigQueryのSQLを自然言語から自動生成する
-- 記事: articles/claude-code-bigquery-sql-auto-generate.md（LIMIT句で結果を確認）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 末尾にLIMITを付けて少量で確認
SELECT ...
FROM ...
LIMIT 10
