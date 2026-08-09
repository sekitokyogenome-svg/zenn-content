-- 93. BigQueryでGA4データのコスト管理・クエリ最適化入門（パターン1：_TABLE_SUFFIXを使わない） その1
-- 用途: パターン1：_TABLE_SUFFIXを使わない
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT event_date, COUNT(*) AS events
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
GROUP BY event_date
ORDER BY event_date
