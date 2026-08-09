-- 187. GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する（チャネル別の新規購入者数を算出するSQL）
-- 用途: チャネル別の新規購入者数を算出するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH first_purchase AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_purchase_timestamp
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

first_purchase_detail AS (
  SELECT
    e.user_pseudo_id,
    CASE
      WHEN e.collected_traffic_source.manual_medium = 'cpc' THEN 'Paid Search'
      WHEN e.collected_traffic_source.manual_medium = 'organic' THEN 'Organic Search'
      WHEN e.collected_traffic_source.manual_medium = 'social' THEN 'Social'
      WHEN e.collected_traffic_source.manual_medium = 'email' THEN 'Email'
      WHEN e.collected_traffic_source.manual_medium = 'referral' THEN 'Referral'
      WHEN e.collected_traffic_source.manual_medium IS NULL
        OR e.collected_traffic_source.manual_medium = '(none)' THEN 'Direct'
      ELSE 'Other'
    END AS channel,
    e.collected_traffic_source.manual_source AS source,
    e.ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*` e
  INNER JOIN first_purchase fp
    ON e.user_pseudo_id = fp.user_pseudo_id
    AND e.event_timestamp = fp.first_purchase_timestamp
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND e.event_name = 'purchase'
)

SELECT
  channel,
  source,
  COUNT(DISTINCT user_pseudo_id) AS new_customers,
  ROUND(SUM(revenue), 0) AS first_purchase_revenue,
  ROUND(AVG(revenue), 0) AS avg_first_purchase_value
FROM first_purchase_detail
GROUP BY channel, source
ORDER BY new_customers DESC
