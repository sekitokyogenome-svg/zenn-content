-- 出典: BigQueryのクエリキャッシュの仕組みを理解してコスト効率を最大化する
-- 記事: articles/bigquery-query-cache-cost-efficiency.md（キャッシュを最大限活用するための運用ポイント）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- キャッシュヒット状況を確認するクエリ
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
