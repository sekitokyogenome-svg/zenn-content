-- 54. GA4×BigQueryでリピーターと新規ユーザーを分離して分析する（新規/リピーター別のセッション指標を比較する）
-- 用途: 新規/リピーター別のセッション指標を比較する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH first_visit_date AS (
  SELECT
    user_pseudo_id,
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_visit_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
),

sessions AS (
  SELECT
    e.user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    CASE
      WHEN f.first_visit_date BETWEEN '2025-03-01' AND '2025-03-31'
      THEN '新規'
      ELSE 'リピーター'
    END AS user_type,
    e.event_name
  FROM `${PROJECT}.${DATASET}.events_*` e
  LEFT JOIN first_visit_date f ON e.user_pseudo_id = f.user_pseudo_id
  WHERE e._TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
)

SELECT
  user_type,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
  ROUND(
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)))
    / COUNT(DISTINCT user_pseudo_id), 2
  ) AS sessions_per_user,
  COUNTIF(event_name = 'purchase') AS purchases,
  ROUND(
    SAFE_DIVIDE(
      COUNTIF(event_name = 'purchase'),
      COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)))
    ) * 100, 2
  ) AS purchase_rate_pct
FROM sessions
GROUP BY user_type
ORDER BY user_type
