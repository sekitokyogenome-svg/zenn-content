-- 出典: GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する
-- 記事: articles/ga4-bigquery-cac-by-channel.md（方法1: 手動でCTEに記述する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH ad_costs AS (
  SELECT 'Paid Search' AS channel, 'google' AS source, 350000 AS monthly_cost UNION ALL
  SELECT 'Paid Search', 'yahoo', 150000 UNION ALL
  SELECT 'Social', 'instagram', 80000 UNION ALL
  SELECT 'Social', 'tiktok', 120000
),

first_purchase AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_purchase_timestamp
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

first_purchase_channel AS (
  SELECT
    e.user_pseudo_id,
    CASE
      WHEN e.collected_traffic_source.manual_medium = 'cpc' THEN 'Paid Search'
      WHEN e.collected_traffic_source.manual_medium = 'social' THEN 'Social'
      ELSE 'Other'
    END AS channel,
    e.collected_traffic_source.manual_source AS source
  FROM `${PROJECT}.${DATASET}.events_*` e
  INNER JOIN first_purchase fp
    ON e.user_pseudo_id = fp.user_pseudo_id
    AND e.event_timestamp = fp.first_purchase_timestamp
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND e.event_name = 'purchase'
    AND e.collected_traffic_source.manual_medium IN ('cpc', 'social')
),

new_customers_by_source AS (
  SELECT
    channel,
    source,
    COUNT(DISTINCT user_pseudo_id) AS new_customers
  FROM first_purchase_channel
  GROUP BY channel, source
)

SELECT
  nc.channel,
  nc.source,
  nc.new_customers,
  ac.monthly_cost,
  ROUND(ac.monthly_cost / NULLIF(nc.new_customers, 0), 0) AS cac
FROM new_customers_by_source nc
INNER JOIN ad_costs ac ON nc.channel = ac.channel AND nc.source = ac.source
ORDER BY cac
