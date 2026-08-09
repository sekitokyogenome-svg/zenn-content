-- 出典: BigQueryのINFORMATION_SCHEMAでクエリコスト・実行履歴を自動監視する
-- 記事: articles/bigquery-information-schema-cost-monitoring.md（ユーザー別・日別のコスト集計でチーム内の利用傾向を掴む）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  DATE(creation_time, 'Asia/Tokyo') AS query_date,
  user_email,
  COUNT(*) AS job_count,
  ROUND(SUM(total_bytes_processed) / POW(1024, 4), 4) AS total_processed_tb,
  ROUND(SUM(total_bytes_processed) / POW(1024, 4) * 6.25, 2) AS estimated_cost_usd
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS
WHERE
  creation_time BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND CURRENT_TIMESTAMP()
  AND job_type = 'QUERY'
  AND state = 'DONE'
  AND error_result IS NULL
GROUP BY
  query_date,
  user_email
ORDER BY
  query_date DESC,
  total_processed_tb DESC;
