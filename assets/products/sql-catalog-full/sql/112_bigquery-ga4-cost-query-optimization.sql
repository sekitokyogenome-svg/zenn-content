-- 112. BigQueryでGA4データのコスト管理・クエリ最適化入門（パターン2：SELECT * を使う） その1
-- 用途: パターン2：SELECT * を使う
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT *
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX = '20260330'
LIMIT 100
