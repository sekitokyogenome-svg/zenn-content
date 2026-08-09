-- 出典: ECサイトのサイト速度がCVRに与える影響をBigQueryのCrUXデータで検証する
-- 記事: articles/ec-site-speed-cvr-bigquery-crux.md（CrUXとGA4データを組み合わせた分析アプローチ）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- スマートフォンのみのLCP中央値
SELECT
  form_factor.name                           AS device_type,
  largest_contentful_paint.percentiles.p75   AS lcp_p75_ms
FROM
  `chrome-ux-report.country_jp.202407`
WHERE
  origin = 'https://your-ec-site.com'
  AND form_factor.name = 'phone'
