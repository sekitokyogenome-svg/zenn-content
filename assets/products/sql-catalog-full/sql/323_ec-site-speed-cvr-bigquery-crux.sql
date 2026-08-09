-- 323. ECサイトのサイト速度がCVRに与える影響をBigQueryのCrUXデータで検証する（CrUXとGA4データを組み合わせた分析アプローチ） その1
-- 用途: CrUXとGA4データを組み合わせた分析アプローチ
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
