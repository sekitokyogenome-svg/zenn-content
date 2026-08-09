-- 出典: Shopify × GA4のエコマース計測でデータが合わない問題を徹底解決する
-- 記事: articles/shopify-ga4-ecommerce-data-mismatch-fix.md（流入元別のpurchase数を確認する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  cs.manual_medium AS medium,
  cs.manual_source AS source,
  COUNT(*) AS purchase_count,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*` AS e
LEFT JOIN
  UNNEST([e.collected_traffic_source]) AS cs
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND e.event_name = 'purchase'
GROUP BY
  medium,
  source
ORDER BY
  purchase_count DESC
