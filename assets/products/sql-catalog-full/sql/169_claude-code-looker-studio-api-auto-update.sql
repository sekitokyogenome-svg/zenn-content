-- 169. Claude Code × Looker Studio APIでダッシュボードを自動更新する
-- 用途: Step 3：BigQueryテーブル変更を検知する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  table_name,
  column_name,
  data_type,
  is_nullable
FROM `${PROJECT}.${DATASET}.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'your_table'
ORDER BY ordinal_position;
