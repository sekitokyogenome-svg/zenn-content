-- 出典: ECサイトのサイト速度がCVRに与える影響をBigQueryのCrUXデータで検証する
-- 記事: articles/ec-site-speed-cvr-bigquery-crux.md（BigQueryでCrUXデータを取得するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  origin,
  -- LCP（良好・要改善・不良の割合）
  ROUND(
    (SELECT value FROM UNNEST(largest_contentful_paint.histogram.bin)
     WHERE start < 2500 LIMIT 1), 4
  ) AS lcp_good_ratio,
  ROUND(
    (SELECT value FROM UNNEST(largest_contentful_paint.histogram.bin)
     WHERE start >= 2500 AND start < 4000 LIMIT 1), 4
  ) AS lcp_needs_improvement_ratio,
  ROUND(
    (SELECT value FROM UNNEST(largest_contentful_paint.histogram.bin)
     WHERE start >= 4000 LIMIT 1), 4
  ) AS lcp_poor_ratio,
  -- LCP中央値
  largest_contentful_paint.percentiles.p75 AS lcp_p75_ms,
  -- FCP中央値
  first_contentful_paint.percentiles.p75 AS fcp_p75_ms
FROM
  `chrome-ux-report.country_jp.202407`
WHERE
  origin = 'https://your-ec-site.com'  -- 自社ドメインに変更
