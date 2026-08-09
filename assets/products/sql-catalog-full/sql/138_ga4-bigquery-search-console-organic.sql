-- 138. GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する（Search Consoleデータの構造を確認する）
-- 用途: Search Consoleデータの構造を確認する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
