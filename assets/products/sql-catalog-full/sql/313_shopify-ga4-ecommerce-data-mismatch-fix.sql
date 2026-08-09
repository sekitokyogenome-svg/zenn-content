-- 313. Shopify × GA4のエコマース計測でデータが合わない問題を徹底解決する（日別のpurchaseイベント件数と売上を確認する）
-- 用途: 日別のpurchaseイベント件数と売上を確認する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
