-- BigQueryのINFORMATION_SCHEMAでクエリコスト・実行履歴を自動監視する
-- 用途: ユーザー別・日別のコスト集計でチーム内の利用傾向を掴む
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
