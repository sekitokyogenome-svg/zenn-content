-- 出典: BigQueryのINFORMATION_SCHEMAでクエリコスト・実行履歴を自動監視する
-- 記事: articles/bigquery-information-schema-cost-monitoring.md（定期監視の仕組みをBigQueryスケジュールクエリで構築する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 前日分のジョブサマリーを集計テーブルに追記する
SELECT
  DATE(creation_time, 'Asia/Tokyo') AS job_date,
  user_email,
  COUNT(*) AS job_count,
  COUNTIF(error_result IS NOT NULL) AS error_count,
  ROUND(SUM(total_bytes_processed) / POW(1024, 4), 6) AS total_processed_tb,
  ROUND(SUM(total_bytes_processed) / POW(1024, 4) * 6.25, 4) AS estimated_cost_usd,
  ROUND(AVG(TIMESTAMP_DIFF(end_time, start_time, SECOND)), 1) AS avg_duration_sec
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS
WHERE
  DATE(creation_time, 'Asia/Tokyo') = DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY)
  AND job_type = 'QUERY'
GROUP BY
  job_date,
  user_email;
