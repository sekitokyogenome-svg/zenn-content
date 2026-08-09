-- BigQueryのクエリキャッシュの仕組みを理解してコスト効率を最大化する
-- 用途: キャッシュを最大限活用するための運用ポイント
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  cache_hit,
  COUNT(*) AS job_count,
  SUM(total_bytes_processed) AS total_bytes
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS
WHERE
  creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND job_type = 'QUERY'
GROUP BY
  cache_hit
