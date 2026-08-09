-- 出典: BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する
-- 記事: articles/bigquery-column-field-paths-ga4-schema.md（実践：GA4テーブルのスキーマ全体を取得する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  field_path,
  data_type
FROM
  `your-project.analytics_XXXXXXXXX`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE
  table_name = 'events_20250101'
ORDER BY
  field_path;
