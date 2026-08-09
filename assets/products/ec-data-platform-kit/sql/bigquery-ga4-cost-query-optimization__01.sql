-- BigQueryでGA4データのコスト管理・クエリ最適化入門
-- 用途: パターン1：_TABLE_SUFFIXを使わない
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT event_date, COUNT(*) AS events
FROM `${PROJECT}.${DATASET}.events_*`
GROUP BY event_date
ORDER BY event_date
