-- BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する
-- 用途: COLUMN_FIELD_PATHSとは
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
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
