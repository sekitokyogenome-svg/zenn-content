-- 出典: GA4×BigQueryでモバイルとPCの購買行動の違いを分析した
-- 記事: articles/ga4-bigquery-mobile-pc-purchase-behavior.md（クロスデバイスの考慮）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- user_idが設定されている場合のクロスデバイス分析
WITH cross_device AS (
  SELECT
    user_id,
    device.category AS device_category,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name IN ('add_to_cart', 'purchase')
    AND user_id IS NOT NULL
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  cart.user_id,
  cart.device_category AS cart_device,
  purchase.device_category AS purchase_device
FROM (
  SELECT DISTINCT user_id, device_category
  FROM cross_device WHERE event_name = 'add_to_cart'
) cart
JOIN (
  SELECT DISTINCT user_id, device_category
  FROM cross_device WHERE event_name = 'purchase'
) purchase
  ON cart.user_id = purchase.user_id
WHERE cart.device_category != purchase.device_category;
