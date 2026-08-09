-- 出典: ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した
-- 記事: articles/chatgpt-claude-gemini-data-analysis-comparison.md（ChatGPTの回答傾向：汎用性は高いが GA4仕様に要注意）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
GROUP BY
  medium, source
ORDER BY
  sessions DESC
