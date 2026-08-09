-- 出典: GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する
-- 記事: articles/ga4-bigquery-search-console-organic.md（Search Consoleデータの構造を確認する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  data_date,
  query,
  url,
  country,
  device,
  impressions,
  clicks,
  sum_position
FROM `your-project.searchconsole.searchdata_url_impression`
WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
ORDER BY clicks DESC
LIMIT 20
