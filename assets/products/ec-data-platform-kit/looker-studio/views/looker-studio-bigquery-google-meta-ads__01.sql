-- Looker Studio × BigQueryでGoogle広告とMeta広告を一画面で比較する
-- 出典: articles/looker-studio-bigquery-google-meta-ads.md

CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.unified_ads_daily` AS

-- Google Ads
SELECT
  segments_date AS date,
  'Google Ads' AS platform,
  campaign_name,
  SUM(metrics_cost_micros / 1000000) AS spend,
  SUM(metrics_impressions) AS impressions,
  SUM(metrics_clicks) AS clicks,
  SUM(metrics_conversions) AS conversions,
  SUM(metrics_conversions_value) AS conversion_value
FROM
  `${PROJECT}.${DATASET}.p_CampaignStats_XXXXXXX` stats
JOIN
  `${PROJECT}.${DATASET}.p_Campaigns_XXXXXXX` campaigns
  ON stats.campaign_id = campaigns.campaign_id
GROUP BY
  date, platform, campaign_name

UNION ALL

-- Meta Ads
SELECT
  date,
  'Meta Ads' AS platform,
  campaign_name,
  SUM(spend) AS spend,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  SUM(purchases) AS conversions,
  SUM(purchase_value) AS conversion_value
FROM
  `${PROJECT}.${DATASET}.meta_ads_daily`
GROUP BY
  date, platform, campaign_name
