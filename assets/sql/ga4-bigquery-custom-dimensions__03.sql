-- 出典: GA4×BigQueryでカスタムディメンションを活用した分析
-- 記事: articles/ga4-bigquery-custom-dimensions.md（user_propertiesからカスタムディメンションを取得する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'membership_tier') AS membership_tier,
  (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'signup_method') AS signup_method
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  AND event_name = 'session_start'
