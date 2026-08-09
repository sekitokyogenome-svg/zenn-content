-- GA4イベントパラメータをUNNESTで展開するSQLパターン集
-- 用途: パターン5：user_propertiesを展開する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(user_properties) WHERE key = 'first_open_time') AS first_open_time,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'user_tier') AS user_tier
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
