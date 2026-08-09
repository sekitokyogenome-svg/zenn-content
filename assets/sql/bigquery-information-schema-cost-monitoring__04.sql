-- 出典: BigQueryのINFORMATION_SCHEMAでクエリコスト・実行履歴を自動監視する
-- 記事: articles/bigquery-information-schema-cost-monitoring.md（アラート設定でコスト超過を早期に検知する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 特定ユーザーの1クエリあたりの最大スキャン量を設定する例（DDL）
ALTER USER `user@example.com`
SET OPTIONS (
  max_query_bytes = 107374182400  -- 100GB
);
