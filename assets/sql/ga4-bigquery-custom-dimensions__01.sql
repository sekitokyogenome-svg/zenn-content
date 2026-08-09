-- 出典: GA4×BigQueryでカスタムディメンションを活用した分析
-- 記事: articles/ga4-bigquery-custom-dimensions.md（基本的な取得パターン）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  event_name,
  event_timestamp,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'button_variant') AS button_variant,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'form_step') AS form_step
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  AND event_name = 'click'
