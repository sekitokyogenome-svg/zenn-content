-- 348. Looker Studioのカスタム指標でROAS・CPAを自動計算する設定（BigQueryで統合広告テーブルを作るSQL）
-- 用途: BigQueryで統合広告テーブルを作るSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.unified_ads_performance` AS

-- Google Ads
SELECT
  segments_date AS date,
  'Google Ads' AS platform,
  campaign_name,
  SUM(metrics_cost_micros / 1000000) AS ad_cost,
  SUM(metrics_clicks) AS clicks,
  SUM(metrics_impressions) AS impressions,
  SUM(metrics_conversions) AS conversions,
  SUM(metrics_conversions_value) AS conversion_value
FROM
  `${PROJECT}.${DATASET}.p_CampaignStats_XXXXXXX`
GROUP BY date, campaign_name

UNION ALL

-- Meta Ads（別途BigQueryに連携済みの想定）
SELECT
  date,
  'Meta Ads' AS platform,
  campaign_name,
  SUM(spend) AS ad_cost,
  SUM(clicks) AS clicks,
  SUM(impressions) AS impressions,
  SUM(purchases) AS conversions,
  SUM(purchase_value) AS conversion_value
FROM
  `${PROJECT}.${DATASET}.meta_ads_daily`
GROUP BY date, campaign_name
