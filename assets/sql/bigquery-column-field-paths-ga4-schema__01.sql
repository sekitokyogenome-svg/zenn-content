-- 出典: BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する
-- 記事: articles/bigquery-column-field-paths-ga4-schema.md（COLUMN_FIELD_PATHSとは）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  field_path,
  data_type,
  description
FROM
  `プロジェクトID.データセット名`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE
  table_name = 'テーブル名'
ORDER BY
  field_path;
