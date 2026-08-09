-- 出典: Yahoo!広告データをBigQueryに取り込んでGoogle広告と統合分析する方法
-- 記事: articles/yahoo-ads-bigquery-google-integrated-analysis.md（媒体横断の集計クエリ実例）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  media_source,
  campaign_name,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  SUM(conversions) AS conversions,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(conversions), SUM(clicks)) * 100, 2) AS cvr_pct
FROM
  `your_project.ads_dataset.unified_ads_stats`
WHERE
  report_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY
  media_source, campaign_name
ORDER BY
  media_source, cvr_pct DESC
;
