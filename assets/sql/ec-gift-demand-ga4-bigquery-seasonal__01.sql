-- 出典: ECのギフト需要をGA4×BigQueryで時系列分析して在庫計画に反映する
-- 記事: articles/ec-gift-demand-ga4-bigquery-seasonal.md（月別・週別の売上推移をBigQueryで時系列分析する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY)) AS week_start,
  COUNT(DISTINCT (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'transaction_id')) AS order_count,
  SUM((SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
  AND event_name = 'purchase'
GROUP BY
  week_start
ORDER BY
  week_start
