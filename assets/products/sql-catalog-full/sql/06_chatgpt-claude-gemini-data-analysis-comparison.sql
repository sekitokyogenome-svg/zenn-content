-- 06. ChatGPT・Claude・GeminiのデータAI分析能力を実データで徹底比較した（Claudeの回答傾向：仕様理解と説明の深さが際立つ）
-- 用途: Claudeの回答傾向：仕様理解と説明の深さが際立つ
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_base AS (
  SELECT
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id') AS session_id,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  GROUP BY
    medium, source, session_id
)
SELECT
  medium,
  source,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS purchases,
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS purchase_rate_pct
FROM
  session_base
GROUP BY
  medium, source
ORDER BY
  sessions DESC
