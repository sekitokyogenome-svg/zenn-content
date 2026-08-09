-- BigQueryのスケジュールクエリでデータマートを毎朝自動更新する設定と監視方法
-- 用途: データの鮮度をSQLで確認する
-- 必要テーブル: INFORMATION_SCHEMA
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  table_name,
  TIMESTAMP_MILLIS(last_modified_time) AS last_modified_jst
FROM
  `${PROJECT}.${DATASET}.INFORMATION_SCHEMA.TABLES`
WHERE
  table_name = 'session_summary'
