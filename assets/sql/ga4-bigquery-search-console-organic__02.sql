-- 出典: GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する
-- 記事: articles/ga4-bigquery-search-console-organic.md（キーワード別パフォーマンス）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  query,
  SUM(impressions) AS total_impressions,
  SUM(clicks) AS total_clicks,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(sum_position), SUM(impressions)), 1) AS avg_position
FROM `your-project.searchconsole.searchdata_url_impression`
WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
  AND query IS NOT NULL
GROUP BY query
HAVING total_impressions >= 10
ORDER BY total_clicks DESC
LIMIT 30
