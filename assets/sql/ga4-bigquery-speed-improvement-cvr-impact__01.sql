-- 出典: GA4×BigQueryでECサイトの速度改善がCVRに与えた影響を測定した
-- 記事: articles/ga4-bigquery-speed-improvement-cvr-impact.md（CrUXデータをBigQueryで活用する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  origin,
  effective_connection_type.name AS connection_type,
  form_factor.name AS device,
  largest_contentful_paint.histogram AS lcp_histogram,
  interaction_to_next_paint.histogram AS inp_histogram,
  cumulative_layout_shift.histogram AS cls_histogram
FROM
  `chrome-ux-report.all.202503`
WHERE
  origin = 'https://your-ec-site.com'
