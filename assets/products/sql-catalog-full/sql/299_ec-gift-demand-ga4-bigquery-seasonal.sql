-- 299. ECのギフト需要をGA4×BigQueryで時系列分析して在庫計画に反映する（流入元別にギフト購入者の行動を分析する）
-- 用途: 流入元別にギフト購入者の行動を分析する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  EXTRACT(MONTH FROM PARSE_DATE('%Y%m%d', event_date)) AS month,
  COUNT(DISTINCT (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'transaction_id')) AS order_count,
  SUM((SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
  AND event_name = 'purchase'
GROUP BY
  medium,
  source,
  month
ORDER BY
  month,
  order_count DESC
