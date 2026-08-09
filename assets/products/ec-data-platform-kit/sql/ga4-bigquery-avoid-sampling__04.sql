-- BigQueryでGA4のサンプリングを回避して正確な数値を出す
-- 用途: _TABLE_SUFFIXで期間を絞る
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT COUNT(*) AS events
FROM `${PROJECT}.${DATASET}.events_*`
