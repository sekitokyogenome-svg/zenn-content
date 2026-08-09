-- 出典: BigQueryのクエリキャッシュの仕組みを理解してコスト効率を最大化する
-- 記事: articles/bigquery-query-cache-cost-efficiency.md（キャッシュが効く条件と効かない条件）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- キャッシュが効かない例（毎回異なる日付が埋め込まれるため）
SELECT
  event_date,
  COUNT(*) AS session_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'session_start'
GROUP BY
  event_date
