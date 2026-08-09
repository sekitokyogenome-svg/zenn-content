-- BigQueryのラベル機能でプロジェクト横断のコスト配分を自動管理する
-- 用途: プロジェクト横断でのコスト配分を自動化するポイント
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
