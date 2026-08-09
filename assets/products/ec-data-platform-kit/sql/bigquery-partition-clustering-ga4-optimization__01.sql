-- BigQueryのパーティション・クラスタリングでGA4クエリを高速化する
-- 用途: GA4エクスポートテーブルの構造を理解する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT COUNT(*) AS event_count
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
