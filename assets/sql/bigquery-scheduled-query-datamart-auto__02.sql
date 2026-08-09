-- 出典: BigQueryのスケジュールクエリでデータマートを毎朝自動更新する設定と監視方法
-- 記事: articles/bigquery-scheduled-query-datamart-auto.md（データの鮮度をSQLで確認する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- テーブルの最終更新日時を確認する
SELECT
  table_name,
  TIMESTAMP_MILLIS(last_modified_time) AS last_modified_jst
FROM
  `${PROJECT}.${DATASET}.INFORMATION_SCHEMA.TABLES`
WHERE
  table_name = 'session_summary'
