-- BigQueryでGA4のサンプリングを回避して正確な数値を出す
-- 用途: _TABLE_SUFFIXで期間を絞る
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT COUNT(*) AS events
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
