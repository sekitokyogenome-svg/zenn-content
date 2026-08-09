-- GA4×BigQueryでカスタムディメンションを活用した分析
-- 用途: event_paramsのキー一覧
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
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
