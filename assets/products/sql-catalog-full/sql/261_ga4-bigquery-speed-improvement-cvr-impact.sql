-- 261. GA4×BigQueryでECサイトの速度改善がCVRに与えた影響を測定した（CrUXデータをBigQueryで活用する）
-- 用途: CrUXデータをBigQueryで活用する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
