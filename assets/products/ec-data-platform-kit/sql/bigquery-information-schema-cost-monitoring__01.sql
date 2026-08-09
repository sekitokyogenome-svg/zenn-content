-- BigQueryのINFORMATION_SCHEMAでクエリコスト・実行履歴を自動監視する
-- 用途: 直近7日間のコスト上位クエリを抽出する
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  job_id,
  user_email,
  query,
  creation_time,
  ROUND(total_bytes_processed / POW(1024, 4), 4) AS processed_tb,
  ROUND(total_bytes_processed / POW(1024, 4) * 6.25, 2) AS estimated_cost_usd,
  TIMESTAMP_DIFF(end_time, start_time, SECOND) AS duration_sec,
  state
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS
WHERE
  creation_time BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND CURRENT_TIMESTAMP()
  AND job_type = 'QUERY'
  AND state = 'DONE'
  AND error_result IS NULL
ORDER BY
  total_bytes_processed DESC
LIMIT 10;
