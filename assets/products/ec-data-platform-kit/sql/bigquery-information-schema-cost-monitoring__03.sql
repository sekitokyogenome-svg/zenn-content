-- BigQueryのINFORMATION_SCHEMAでクエリコスト・実行履歴を自動監視する
-- 用途: 定期監視の仕組みをBigQueryスケジュールクエリで構築する
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
