-- 出典: GA4×BigQueryでカスタムディメンションを活用した分析
-- 記事: articles/ga4-bigquery-custom-dimensions.md（event_paramsのキー一覧）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  ep.key,
  COUNT(*) AS occurrences,
  COUNTIF(ep.value.string_value IS NOT NULL) AS has_string,
  COUNTIF(ep.value.int_value IS NOT NULL) AS has_int,
  COUNTIF(ep.value.float_value IS NOT NULL) AS has_float
FROM `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) AS ep
WHERE _TABLE_SUFFIX = '20250330'
GROUP BY ep.key
ORDER BY occurrences DESC
