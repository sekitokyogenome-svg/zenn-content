-- 142. Claude Codeに競合サイトの施策をGA4データから推測させた話（Step 1：トレンド変化を検出するSQLを用意する）
-- 用途: Step 1：トレンド変化を検出するSQLを用意する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH sessions AS (
  SELECT
    DATE_TRUNC(
      PARSE_DATE('%Y%m%d', event_date), WEEK
    ) AS week_start,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),
weekly_metrics AS (
  SELECT
    week_start,
    CONCAT(IFNULL(source, '(direct)'), ' / ', IFNULL(medium, '(none)')) AS channel,
    COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(session_id AS STRING))) AS sessions
  FROM sessions
  GROUP BY week_start, channel
)
SELECT
  week_start,
  channel,
  sessions,
  LAG(sessions) OVER (PARTITION BY channel ORDER BY week_start) AS prev_week_sessions,
  SAFE_DIVIDE(
    sessions - LAG(sessions) OVER (PARTITION BY channel ORDER BY week_start),
    LAG(sessions) OVER (PARTITION BY channel ORDER BY week_start)
  ) AS wow_change_rate
FROM weekly_metrics
ORDER BY week_start DESC, sessions DESC;
