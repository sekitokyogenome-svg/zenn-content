-- 出典: Claude Code × Looker Studio APIでダッシュボードを自動更新する
-- 記事: articles/claude-code-looker-studio-api-auto-update.md（Step 3：BigQueryテーブル変更を検知する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- テーブルのカラム情報を取得
SELECT
  table_name,
  column_name,
  data_type,
  is_nullable
FROM `${PROJECT}.${DATASET}.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'your_table'
ORDER BY ordinal_position;
