-- Claude Codeで複数広告媒体のROASを一括比較するスクリプトを作成した
-- 用途: テーブル設計
-- 必要テーブル: raw_google_ads, raw_line_ads, raw_meta_ads, unified_ad_performance
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.unified_ad_performance` AS

-- Google Ads
SELECT
  'google' AS platform,
  segments_date AS date,
  campaign_name,
  metrics_cost_micros / 1000000 AS cost,
  metrics_conversions AS conversions,
  metrics_conversions_value AS conversion_value,
  metrics_clicks AS clicks,
  metrics_impressions AS impressions
FROM
  `${PROJECT}.${DATASET}.raw_google_ads`

UNION ALL

-- Meta Ads
SELECT
  'meta' AS platform,
  date_start AS date,
  campaign_name,
  spend AS cost,
  CAST(actions_purchase AS FLOAT64) AS conversions,
  action_values_purchase AS conversion_value,
  clicks,
  impressions
FROM
  `${PROJECT}.${DATASET}.raw_meta_ads`

UNION ALL

-- LINE Ads
SELECT
  'line' AS platform,
  report_date AS date,
  campaign_name,
  cost,
  conversions,
  conversion_value,
  clicks,
  impressions
FROM
  `${PROJECT}.${DATASET}.raw_line_ads`
