-- 出典: BigQueryのマテリアライズドビューでGA4集計クエリを高速化した
-- 記事: articles/bigquery-materialized-view-ga4-speedup.md（マテリアライズドビューの作成手順）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- マテリアライズドビューへのクエリ例
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
