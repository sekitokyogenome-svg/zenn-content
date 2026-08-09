-- 456. Yahoo!広告データをBigQueryに取り込んでGoogle広告と統合分析する方法（BigQueryにおける統合テーブルの設計方針）
-- 用途: BigQueryにおける統合テーブルの設計方針
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE VIEW `your_project.ads_dataset.unified_ads_stats` AS

-- Google広告データ
SELECT
  'google' AS media_source,
  DATE(segments.date) AS report_date,
  campaign.name AS campaign_name,
  metrics.impressions AS impressions,
  metrics.clicks AS clicks,
  ROUND(metrics.cost_micros / 1000000, 2) AS cost_jpy,
  metrics.conversions AS conversions
FROM
  `your_project.google_ads.p_ads_CampaignBasicStats_*`

UNION ALL

-- Yahoo!広告データ（取り込み済みのテーブルを参照）
SELECT
  'yahoo' AS media_source,
  report_date,
  campaign_name,
  impressions,
  clicks,
  cost AS cost_jpy,
  conversions
FROM
  `your_project.yahoo_ads.campaign_report`
;
