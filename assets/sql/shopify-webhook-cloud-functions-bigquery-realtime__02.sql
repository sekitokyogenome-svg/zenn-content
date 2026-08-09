-- 出典: ShopifyのWebhook × Cloud Functions × BigQueryでリアルタイム売上基盤を作る
-- 記事: articles/shopify-webhook-cloud-functions-bigquery-realtime.md（BigQueryで売上を集計・分析する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  DATE(TIMESTAMP(created_at)) AS order_date,
  COUNT(DISTINCT order_id)   AS order_count,
  ROUND(SUM(total_price), 0) AS total_revenue,
  currency
FROM
  `your-project-id.shopify_raw.orders`
WHERE
  financial_status = 'paid'
  AND DATE(TIMESTAMP(created_at)) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY
  order_date, currency
ORDER BY
  order_date DESC;
