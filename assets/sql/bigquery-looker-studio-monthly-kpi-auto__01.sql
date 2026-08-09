-- 出典: BigQuery × Looker StudioでEC事業の月次KPIレポートを自動化した
-- 記事: articles/bigquery-looker-studio-monthly-kpi-auto.md（mart層のKPIビュー）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.mart_monthly_kpi` AS
WITH sessions AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), MONTH) AS month,
    CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    user_pseudo_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    device.category AS device,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase,
    SUM(CASE WHEN event_name = 'purchase' THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 13 MONTH))
  GROUP BY
    month, session_id, user_pseudo_id, source, medium, device
)

SELECT
  month,
  COUNT(DISTINCT session_id) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  SUM(has_purchase) AS purchases,
  SUM(revenue) AS revenue,
  SAFE_DIVIDE(SUM(has_purchase), COUNT(DISTINCT session_id)) AS cvr,
  SAFE_DIVIDE(SUM(revenue), COUNT(DISTINCT session_id)) AS revenue_per_session,
  SAFE_DIVIDE(SUM(revenue), SUM(has_purchase)) AS avg_order_value
FROM
  sessions
GROUP BY
  month
ORDER BY
  month DESC
