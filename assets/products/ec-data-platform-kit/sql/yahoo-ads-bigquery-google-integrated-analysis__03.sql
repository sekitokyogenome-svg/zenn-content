-- Yahoo!広告データをBigQueryに取り込んでGoogle広告と統合分析する方法
-- 用途: 媒体横断の集計クエリ実例
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
