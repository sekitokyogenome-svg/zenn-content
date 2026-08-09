-- 99. GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する（キーワード別パフォーマンス）
-- 用途: キーワード別パフォーマンス
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
