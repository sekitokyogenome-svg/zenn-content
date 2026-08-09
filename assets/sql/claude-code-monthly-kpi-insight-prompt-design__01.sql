-- 出典: Claude Codeに月次KPIレポートの「考察」まで書かせるプロンプト設計術
-- 記事: articles/claude-code-monthly-kpi-insight-prompt-design.md（BigQueryでGA4データを集計するSQL設計）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH session_base AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_name,
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
),

sessions AS (
  SELECT
    month,
    medium,
    source,
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions
  FROM session_base
  GROUP BY 1, 2, 3
),

conversions AS (
  SELECT
    month,
    medium,
    source,
    COUNT(*) AS cv_count
  FROM session_base
  WHERE event_name = 'purchase'
  GROUP BY 1, 2, 3
)

SELECT
  s.month,
  s.medium,
  s.source,
  s.sessions,
  COALESCE(c.cv_count, 0) AS cv_count,
  ROUND(SAFE_DIVIDE(COALESCE(c.cv_count, 0), s.sessions) * 100, 2) AS cvr
FROM sessions s
LEFT JOIN conversions c
  ON s.month = c.month AND s.medium = c.medium AND s.source = c.source
ORDER BY s.sessions DESC
