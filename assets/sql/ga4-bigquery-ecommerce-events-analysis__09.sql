-- 出典: BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】
-- 記事: articles/ga4-bigquery-ecommerce-events-analysis.md（eコマーストラッキングの検証Tips）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- トラッキング健全性チェック
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
