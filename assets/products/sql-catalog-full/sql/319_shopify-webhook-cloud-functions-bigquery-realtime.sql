-- 319. ShopifyのWebhook × Cloud Functions × BigQueryでリアルタイム売上基盤を作る（BigQueryで売上を集計・分析する） その2
-- 用途: BigQueryで売上を集計・分析する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
