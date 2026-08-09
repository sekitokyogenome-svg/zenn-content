-- 194. GA4×BigQueryでメルマガのROIを正確に測定する（セッションをまたいだアトリビューション）
-- 用途: セッションをまたいだアトリビューション
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH email_clicks AS (
  -- メルマガ経由で訪問したユーザーとその日時
  SELECT
    user_pseudo_id,
    collected_traffic_source.manual_campaign AS campaign,
    MIN(TIMESTAMP_MICROS(event_timestamp)) AS email_click_time
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'email'
    AND event_name = 'session_start'
  GROUP BY user_pseudo_id, campaign
),

purchases AS (
  SELECT
    user_pseudo_id,
    TIMESTAMP_MICROS(event_timestamp) AS purchase_time,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
)

SELECT
  ec.campaign,
  COUNT(DISTINCT ec.user_pseudo_id) AS email_visitors,
  -- 直接CV（同日購入）
  COUNT(DISTINCT IF(
    DATE(p.purchase_time) = DATE(ec.email_click_time),
    ec.user_pseudo_id, NULL
  )) AS same_day_purchasers,
  -- 間接CV（7日以内に購入）
  COUNT(DISTINCT IF(
    p.purchase_time BETWEEN ec.email_click_time AND TIMESTAMP_ADD(ec.email_click_time, INTERVAL 7 DAY),
    ec.user_pseudo_id, NULL
  )) AS purchasers_within_7d,
  -- 7日以内の売上合計
  ROUND(SUM(IF(
    p.purchase_time BETWEEN ec.email_click_time AND TIMESTAMP_ADD(ec.email_click_time, INTERVAL 7 DAY),
    p.revenue, 0
  )), 0) AS revenue_within_7d
FROM email_clicks ec
LEFT JOIN purchases p ON ec.user_pseudo_id = p.user_pseudo_id
  AND p.purchase_time >= ec.email_click_time
GROUP BY ec.campaign
ORDER BY revenue_within_7d DESC
