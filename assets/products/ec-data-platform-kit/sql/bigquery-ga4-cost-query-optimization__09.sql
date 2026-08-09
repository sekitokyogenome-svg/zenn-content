-- BigQueryでGA4データのコスト管理・クエリ最適化入門
-- 用途: 月額コストの見積もり方
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  _TABLE_SUFFIX AS table_date,
  COUNT(*) AS row_count,
  SUM(OCTET_LENGTH(TO_JSON_STRING(t))) / 1024 / 1024 AS approx_mb
FROM `${PROJECT}.${DATASET}.events_*` t
WHERE _TABLE_SUFFIX = '20260330'
GROUP BY table_date
