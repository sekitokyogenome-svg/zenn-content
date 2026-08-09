-- 296. BASE・STORES・ShopifyのGA4計測精度を比較検証した【2026年版】（Shopify：GA4計測の拡張性は最も高いが設定コストも高い）
-- 用途: Shopify：GA4計測の拡張性は最も高いが設定コストも高い
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNT(*) AS purchase_events,
  SUM(
    (SELECT value.double_value
     FROM UNNEST(event_params)
     WHERE key = 'value')
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260701' AND '20260731'
  AND event_name = 'purchase'
GROUP BY
  medium, source
ORDER BY
  total_revenue DESC
