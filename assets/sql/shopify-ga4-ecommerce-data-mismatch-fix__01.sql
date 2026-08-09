-- 出典: Shopify × GA4のエコマース計測でデータが合わない問題を徹底解決する
-- 記事: articles/shopify-ga4-ecommerce-data-mismatch-fix.md（日別のpurchaseイベント件数と売上を確認する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
  COUNT(*) AS purchase_count,
  SUM(ecommerce.purchase_revenue) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND event_name = 'purchase'
GROUP BY
  event_date
ORDER BY
  event_date
