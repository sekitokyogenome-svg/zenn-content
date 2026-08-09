-- BigQueryでEC季節商品の売上予測モデルを作った話
-- 出典: articles/bigquery-ec-seasonal-sales-prediction.md

CREATE OR REPLACE TABLE `your-project.mart.daily_sales` AS
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS sale_date,
  SUM(ecommerce.purchase_revenue) AS daily_revenue,
  COUNT(DISTINCT user_pseudo_id) AS unique_buyers,
  COUNT(*) AS transaction_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20251231'
  AND event_name = 'purchase'
  AND ecommerce.purchase_revenue > 0
GROUP BY sale_date
ORDER BY sale_date
