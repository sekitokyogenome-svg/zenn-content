-- 出典: Claude CodeにGA4の異常値を検知させて原因仮説まで出力させるプロンプト設計
-- 記事: articles/claude-code-ga4-anomaly-detection-prompt.md（異常値を取得するBigQueryクエリの設計）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH session_base AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    user_pseudo_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    event_name
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
),
sessions AS (
  SELECT
    date,
    medium,
    source,
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions
  FROM session_base
  GROUP BY 1, 2, 3
),
purchases AS (
  SELECT
    date,
    medium,
    source,
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS conversions
  FROM session_base
  WHERE event_name = 'purchase'
  GROUP BY 1, 2, 3
)
SELECT
  s.date,
  s.medium,
  s.source,
  s.sessions,
  COALESCE(p.conversions, 0) AS conversions,
  SAFE_DIVIDE(COALESCE(p.conversions, 0), s.sessions) AS cvr
FROM sessions s
LEFT JOIN purchases p
  ON s.date = p.date AND s.medium = p.medium AND s.source = p.source
ORDER BY s.date DESC, s.sessions DESC
