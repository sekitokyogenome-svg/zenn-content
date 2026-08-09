-- 97. GA4×BigQueryでカスタムディメンションを活用した分析（user_propertiesのキー一覧）
-- 用途: user_propertiesのキー一覧
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
