-- 出典: GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する
-- 記事: articles/ga4-bigquery-search-console-organic.md（キーワード × ランディングページの分析）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  query,
  REGEXP_EXTRACT(url, r'^https?://[^/]+(/.*)') AS page_path,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  ROUND(SAFE_DIVIDE(SUM(clicks), SUM(impressions)) * 100, 2) AS ctr_pct,
  ROUND(SAFE_DIVIDE(SUM(sum_position), SUM(impressions)), 1) AS avg_position
FROM `your-project.searchconsole.searchdata_url_impression`
WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
  AND url LIKE '%/blog/%'
  AND query IS NOT NULL
GROUP BY query, page_path
HAVING clicks >= 2
ORDER BY clicks DESC
LIMIT 50
