-- 出典: AIコーディングアシスタント3種でBigQueryのデータパイプラインを作り比べた
-- 記事: articles/ai-coding-assistant-bigquery-pipeline-comparison.md（Claude（Anthropic）の評価）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- セッション別の流入元とCV数を集計するクエリ
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS conversions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  event_date, medium, source
ORDER BY
  event_date DESC, sessions DESC
