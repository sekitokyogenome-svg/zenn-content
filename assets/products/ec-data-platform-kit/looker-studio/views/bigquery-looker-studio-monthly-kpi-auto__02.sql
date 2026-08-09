-- BigQuery × Looker StudioでEC事業の月次KPIレポートを自動化した
-- 出典: articles/bigquery-looker-studio-monthly-kpi-auto.md

CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.mart_monthly_kpi_with_ads` AS
SELECT
  kpi.month,
  kpi.sessions,
  kpi.users,
  kpi.purchases,
  kpi.revenue,
  kpi.cvr,
  kpi.revenue_per_session,
  kpi.avg_order_value,
  ads.ad_cost,
  SAFE_DIVIDE(kpi.revenue, ads.ad_cost) AS roas,
  SAFE_DIVIDE(ads.ad_cost, kpi.purchases) AS cpa
FROM
  `${PROJECT}.${DATASET}.mart_monthly_kpi` kpi
LEFT JOIN (
  SELECT
    DATE_TRUNC(segments_date, MONTH) AS month,
    SUM(metrics_cost_micros / 1000000) AS ad_cost
  FROM
    `${PROJECT}.${DATASET}.p_CampaignStats_XXXXXXX`
  GROUP BY month
) ads ON kpi.month = ads.month
