-- 出典: GA4×BigQueryでカスタムディメンションを活用した分析
-- 記事: articles/ga4-bigquery-custom-dimensions.md（user_propertiesの注意点）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH latest_properties AS (
  SELECT
    user_pseudo_id,
    prop.key AS property_key,
    prop.value.string_value AS property_value,
    prop.value.set_timestamp_micros AS set_timestamp,
    ROW_NUMBER() OVER (
      PARTITION BY user_pseudo_id, prop.key
      ORDER BY prop.value.set_timestamp_micros DESC
    ) AS rn
  FROM `${PROJECT}.${DATASET}.events_*`,
    UNNEST(user_properties) AS prop
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND prop.key = 'membership_tier'
)
SELECT
  user_pseudo_id,
  property_value AS membership_tier
FROM latest_properties
WHERE rn = 1
