-- 385. BigQueryのマテリアライズドビューでGA4集計クエリを高速化した（マテリアライズドビューの作成手順） その2
-- 用途: マテリアライズドビューの作成手順
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_date,
  source,
  medium,
  COUNT(DISTINCT ga_session_id) AS sessions,
  SUM(purchase_count) AS purchases,
  SUM(total_revenue) AS revenue
FROM
  `${PROJECT}.${DATASET}.mv_ga4_session_summary`
WHERE
  event_date BETWEEN '2025-06-01' AND '2025-06-30'
GROUP BY
  event_date,
  source,
  medium
ORDER BY
  event_date DESC
