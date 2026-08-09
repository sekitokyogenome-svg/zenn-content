-- 389. BigQueryのクエリキャッシュの仕組みを理解してコスト効率を最大化する（キャッシュが効く条件と効かない条件）
-- 用途: キャッシュが効く条件と効かない条件
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
