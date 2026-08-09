-- 100. GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する（ランディングページ別パフォーマンス）
-- 用途: ランディングページ別パフォーマンス
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  REGEXP_EXTRACT(url, r'^https?://[^/]+(/.*)') AS page_path,
  SUM(impressions) AS total_impressions,
  SUM(clicks) AS total_clicks,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(sum_position), SUM(impressions)), 1) AS avg_position,
  COUNT(DISTINCT query) AS unique_queries
FROM `your-project.searchconsole.searchdata_url_impression`
WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
GROUP BY page_path
ORDER BY total_clicks DESC
LIMIT 20
