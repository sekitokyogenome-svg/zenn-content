-- 101. BigQueryでGA4データのコスト管理・クエリ最適化入門（パターン1：_TABLE_SUFFIXを使わない） その2
-- 用途: パターン1：_TABLE_SUFFIXを使わない
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT event_date, COUNT(*) AS events
FROM `${PROJECT}.${DATASET}.events_*`
GROUP BY event_date
ORDER BY event_date
