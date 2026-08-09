-- 出典: ECサイトのサイト速度がCVRに与える影響をBigQueryのCrUXデータで検証する
-- 記事: articles/ec-site-speed-cvr-bigquery-crux.md（CrUXとGA4データを組み合わせた分析アプローチ）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  PARSE_DATE('%Y%m', CAST(yyyymm AS STRING)) AS month,
  largest_contentful_paint.percentiles.p75   AS lcp_p75_ms
FROM (
  SELECT 202405 AS yyyymm, largest_contentful_paint
  FROM `chrome-ux-report.country_jp.202405`
  WHERE origin = 'https://your-ec-site.com'
  UNION ALL
  SELECT 202406, largest_contentful_paint
  FROM `chrome-ux-report.country_jp.202406`
  WHERE origin = 'https://your-ec-site.com'
  UNION ALL
  SELECT 202407, largest_contentful_paint
  FROM `chrome-ux-report.country_jp.202407`
  WHERE origin = 'https://your-ec-site.com'
)
ORDER BY month;
