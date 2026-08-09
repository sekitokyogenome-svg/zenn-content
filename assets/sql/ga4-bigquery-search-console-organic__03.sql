-- 出典: GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する
-- 記事: articles/ga4-bigquery-search-console-organic.md（ランディングページ別パフォーマンス）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
