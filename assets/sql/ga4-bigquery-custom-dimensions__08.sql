-- 出典: GA4×BigQueryでカスタムディメンションを活用した分析
-- 記事: articles/ga4-bigquery-custom-dimensions.md（user_propertiesのキー一覧）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  prop.key,
  COUNT(*) AS occurrences,
  COUNTIF(prop.value.string_value IS NOT NULL) AS has_string,
  COUNTIF(prop.value.int_value IS NOT NULL) AS has_int
FROM `${PROJECT}.${DATASET}.events_*`,
  UNNEST(user_properties) AS prop
WHERE _TABLE_SUFFIX = '20250330'
GROUP BY prop.key
ORDER BY occurrences DESC
