-- Looker Studio × BigQueryでGoogle広告とMeta広告を一画面で比較する
-- 用途: KPI集計ビュー
-- 必要テーブル: ads_platform_comparison, unified_ads_daily
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.ads_platform_comparison` AS
SELECT
  platform,
  SUM(spend) AS total_spend,
  SUM(impressions) AS total_impressions,
  SUM(clicks) AS total_clicks,
  SUM(conversions) AS total_conversions,
  SUM(conversion_value) AS total_conversion_value,
  SAFE_DIVIDE(SUM(clicks), SUM(impressions)) AS ctr,
  SAFE_DIVIDE(SUM(conversions), SUM(clicks)) AS cvr,
  SAFE_DIVIDE(SUM(spend), SUM(clicks)) AS cpc,
  SAFE_DIVIDE(SUM(spend), SUM(conversions)) AS cpa,
  SAFE_DIVIDE(SUM(conversion_value), SUM(spend)) AS roas
FROM
  `${PROJECT}.${DATASET}.unified_ads_daily`
WHERE
  date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY
  platform
