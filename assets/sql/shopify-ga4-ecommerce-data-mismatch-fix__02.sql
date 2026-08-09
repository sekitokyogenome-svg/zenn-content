-- 出典: Shopify × GA4のエコマース計測でデータが合わない問題を徹底解決する
-- 記事: articles/shopify-ga4-ecommerce-data-mismatch-fix.md（transaction_idの重複を確認する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  ep.value.string_value AS transaction_id,
  COUNT(*) AS send_count
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) AS ep
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND event_name = 'purchase'
  AND ep.key = 'transaction_id'
GROUP BY
  transaction_id
HAVING
  send_count > 1
ORDER BY
  send_count DESC
