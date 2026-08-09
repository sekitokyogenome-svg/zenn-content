-- GA4×BigQueryでカスタムディメンションを活用した分析
-- 用途: 基本的な取得パターン
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_name,
  event_timestamp,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'button_variant') AS button_variant,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'form_step') AS form_step
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  AND event_name = 'click'
