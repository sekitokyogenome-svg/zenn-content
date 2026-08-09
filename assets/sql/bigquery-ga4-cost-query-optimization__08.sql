-- 出典: BigQueryでGA4データのコスト管理・クエリ最適化入門
-- 記事: articles/bigquery-ga4-cost-query-optimization.md（テクニック4：ドライランで事前にスキャン量を確認する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- bqコマンドでドライラン
-- bq query --dry_run --use_legacy_sql=false 'SELECT ...'
