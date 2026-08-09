-- Looker Studio × BigQueryでEC売上ダッシュボードを1日で作る完全手順
-- 出典: articles/looker-studio-bigquery-ec-dashboard-guide.md

CREATE OR REPLACE VIEW `your_project.your_mart_dataset.mart_dashboard_daily` AS
WITH sessions AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    device.category AS device_category,
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-',
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id'))
    ) AS sessions
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  GROUP BY date, source, medium, device_category
),

purchases AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    device.category AS device_category,
    COUNT(DISTINCT ecommerce.transaction_id) AS transactions,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  GROUP BY date, source, medium, device_category
)

SELECT
  s.date,
  COALESCE(s.source, '(direct)') AS source,
  COALESCE(s.medium, '(none)') AS medium,
  s.device_category,
  s.sessions,
  COALESCE(p.transactions, 0) AS transactions,
  COALESCE(p.revenue, 0) AS revenue,
  SAFE_DIVIDE(COALESCE(p.transactions, 0), s.sessions) AS cvr,
  SAFE_DIVIDE(COALESCE(p.revenue, 0), COALESCE(p.transactions, 0)) AS aov
FROM sessions s
LEFT JOIN purchases p
  ON s.date = p.date
  AND COALESCE(s.source, '') = COALESCE(p.source, '')
  AND COALESCE(s.medium, '') = COALESCE(p.medium, '')
  AND s.device_category = p.device_category
ORDER BY s.date DESC;
