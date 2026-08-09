-- BigQueryでGA4の生データ構造を理解する【eventsテーブル解説】
-- 用途: user_propertiesの展開
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  user_pseudo_id,
  (SELECT value.string_value
   FROM UNNEST(user_properties)
   WHERE key = 'membership_level') AS membership_level
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
