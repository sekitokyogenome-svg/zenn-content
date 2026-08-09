-- 出典: AIコーディングアシスタント3種でBigQueryのデータパイプラインを作り比べた
-- 記事: articles/ai-coding-assistant-bigquery-pipeline-comparison.md（Gemini（Google）の評価）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  event_date,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS session_count,
  COUNTIF(event_name = 'purchase') AS cv_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
GROUP BY 1, 2, 3
ORDER BY 1 DESC
