-- 出典: Claude Codeで複数広告媒体のROASを一括比較するスクリプトを作成した
-- 記事: articles/claude-code-multi-ad-roas-comparison.md（テーブル設計）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 広告データ統合ビュー
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
