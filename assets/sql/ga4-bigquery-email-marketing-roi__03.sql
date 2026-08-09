-- 出典: GA4×BigQueryでメルマガのROIを正確に測定する
-- 記事: articles/ga4-bigquery-email-marketing-roi.md（ROIを算出する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 配信コストをキャンペーンごとに手動で設定する例
WITH campaign_costs AS (
  SELECT 'spring_sale_2025' AS campaign, 15000 AS cost UNION ALL
  SELECT 'weekly_20250301', 5000 UNION ALL
  SELECT 'weekly_20250308', 5000 UNION ALL
  SELECT 'weekly_20250315', 5000
),

email_revenue AS (
  SELECT
    collected_traffic_source.manual_campaign AS campaign,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND collected_traffic_source.manual_medium = 'email'
    AND event_name = 'purchase'
  GROUP BY campaign
)

SELECT
  er.campaign,
  cc.cost,
  ROUND(er.revenue, 0) AS revenue,
  ROUND((er.revenue - cc.cost) / cc.cost * 100, 1) AS roi_pct
FROM email_revenue er
INNER JOIN campaign_costs cc ON er.campaign = cc.campaign
ORDER BY roi_pct DESC
