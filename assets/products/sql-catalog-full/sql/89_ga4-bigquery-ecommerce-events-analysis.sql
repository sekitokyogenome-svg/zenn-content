-- 89. BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】（eコマーストラッキングの検証Tips）
-- 用途: eコマーストラッキングの検証Tips
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  COUNT(*) AS purchase_events,
  COUNT(DISTINCT ecommerce.transaction_id) AS unique_transactions,
  COUNTIF(ARRAY_LENGTH(items) = 0) AS empty_items_count,
  ROUND(AVG(ecommerce.purchase_revenue), 0) AS avg_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
  AND event_name = 'purchase'
GROUP BY
  event_date
ORDER BY
  date
