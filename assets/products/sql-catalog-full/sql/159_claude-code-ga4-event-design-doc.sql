-- 159. Claude CodeでGA4のイベント設計書を自動生成する方法（Step 2: ecommerce関連イベントの詳細を取得する）
-- 用途: Step 2: ecommerce関連イベントの詳細を取得する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS unique_sessions,
  SUM(ecommerce.purchase_revenue) AS total_revenue,
  COUNT(DISTINCT ecommerce.transaction_id) AS unique_transactions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name IN (
    'view_item', 'add_to_cart', 'begin_checkout',
    'add_payment_info', 'add_shipping_info', 'purchase'
  )
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  event_name
ORDER BY
  event_count DESC
