-- 出典: Google広告データをBigQuery Data Transfer Serviceで自動連携する完全手順
-- 記事: articles/google-ads-bigquery-dts-setup-guide.md（キャンペーン別コストとコンバージョンを確認するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  campaign.name AS campaign_name,
  metrics.impressions AS impressions,
  metrics.clicks AS clicks,
  ROUND(metrics.cost_micros / 1000000, 0) AS cost_jpy,
  metrics.conversions AS conversions,
  SAFE_DIVIDE(
    ROUND(metrics.cost_micros / 1000000, 0),
    metrics.conversions
  ) AS cpa
FROM
  `YOUR_PROJECT.google_ads_transfer.ads_Campaign_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
ORDER BY
  cost_jpy DESC
LIMIT 20;
