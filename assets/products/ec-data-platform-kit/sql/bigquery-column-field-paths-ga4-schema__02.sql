-- BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する
-- 用途: 実践：GA4テーブルのスキーマ全体を取得する
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  field_path,
  data_type
FROM
  `your-project.analytics_XXXXXXXXX`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE
  table_name = 'events_20250101'
ORDER BY
  field_path;
