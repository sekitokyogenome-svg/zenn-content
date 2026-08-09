-- 412. BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する（特定フィールドだけを絞り込んで探索する） その1
-- 用途: 特定フィールドだけを絞り込んで探索する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  field_path,
  data_type
FROM
  `your-project.analytics_XXXXXXXXX`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE
  table_name = 'events_20250101'
  AND field_path LIKE 'items%'
ORDER BY
  field_path;
