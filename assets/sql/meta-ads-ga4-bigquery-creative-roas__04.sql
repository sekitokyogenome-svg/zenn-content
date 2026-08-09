-- 出典: Meta広告×GA4×BigQueryでクリエイティブ別ROASを深掘りする
-- 記事: articles/meta-ads-ga4-bigquery-creative-roas.md（フォーマット別の傾向分析）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  CASE
    WHEN creative_name LIKE '%video%' THEN 'video'
    WHEN creative_name LIKE '%static%' THEN 'static'
    WHEN creative_name LIKE '%carousel%' THEN 'carousel'
    ELSE 'other'
  END AS format_type,
  SUM(sessions) AS total_sessions,
  SUM(purchases) AS total_purchases,
  SUM(total_revenue) AS total_revenue,
  SUM(total_spend) AS total_spend,
  ROUND(SAFE_DIVIDE(SUM(total_revenue), SUM(total_spend)), 2) AS roas
FROM creative_performance
GROUP BY format_type
ORDER BY roas DESC;
