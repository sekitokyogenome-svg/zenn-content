-- 出典: GA4×BigQueryのテーブル肥大化を防ぐパーティション有効期限の設定方法
-- 記事: articles/ga4-bigquery-table-partition-expiry.md（方法1：テーブル有効期限（Table Expiration）でシャードを自動削除する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 特定のテーブルに有効期限を設定する例（例：2025年1月1日のシャード）
ALTER TABLE `${PROJECT}.${DATASET}.events_20250101`
SET OPTIONS (
  expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 365 DAY)
);
