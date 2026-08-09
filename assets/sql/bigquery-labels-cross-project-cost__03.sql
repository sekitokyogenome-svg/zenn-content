-- 出典: BigQueryのラベル機能でプロジェクト横断のコスト配分を自動管理する
-- 記事: articles/bigquery-labels-cross-project-cost.md（プロジェクト横断でのコスト配分を自動化するポイント）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- ラベルが付与されていないBigQueryジョブを検出するクエリ
SELECT
  job_id,
  user_email,
  total_bytes_processed,
  creation_time,
  labels
FROM
  `region-asia-northeast1`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE
  DATE(creation_time) = CURRENT_DATE() - 1
  AND ARRAY_LENGTH(labels) = 0
  AND job_type = 'QUERY'
ORDER BY
  total_bytes_processed DESC
LIMIT 50
