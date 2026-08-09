-- BigQueryでGA4データのコスト管理・クエリ最適化入門
-- 用途: パターン2：SELECT * を使う
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT event_date, event_name, user_pseudo_id
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX = '20260330'
LIMIT 100
