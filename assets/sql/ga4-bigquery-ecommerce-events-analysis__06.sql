-- 出典: BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】
-- 記事: articles/ga4-bigquery-ecommerce-events-analysis.md（カテゴリ別・商品別の売上集計）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT ecommerce.transaction_id) AS transactions,
  ROUND(SUM(ecommerce.purchase_revenue), 0) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
  AND event_name = 'purchase'
GROUP BY
  medium, source
ORDER BY
  total_revenue DESC
