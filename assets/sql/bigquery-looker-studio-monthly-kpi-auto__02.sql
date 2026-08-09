-- 出典: BigQuery × Looker StudioでEC事業の月次KPIレポートを自動化した
-- 記事: articles/bigquery-looker-studio-monthly-kpi-auto.md（広告データとの統合ビュー）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
