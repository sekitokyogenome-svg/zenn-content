-- BigQuery × Looker StudioでEC事業の月次KPIレポートを自動化した
-- 用途: 広告データとの統合ビュー
-- 必要テーブル: mart_monthly_kpi, mart_monthly_kpi_with_ads, p_CampaignStats_XXXXXXX
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
