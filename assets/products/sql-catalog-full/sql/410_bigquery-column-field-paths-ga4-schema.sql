-- 410. BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する（COLUMN_FIELD_PATHSとは）
-- 用途: COLUMN_FIELD_PATHSとは
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
