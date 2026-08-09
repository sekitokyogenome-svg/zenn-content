-- 96. GA4×BigQueryでカスタムディメンションを活用した分析（event_paramsのキー一覧）
-- 用途: event_paramsのキー一覧
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
