-- GA4×BigQueryでリピーターと新規ユーザーを分離して分析する
-- 用途: 新規/リピーター別のチャネル分析
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH first_visit_date AS (
  SELECT
    user_pseudo_id,
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_visit_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
)

SELECT
  CASE
    WHEN f.first_visit_date BETWEEN '2025-03-01' AND '2025-03-31'
    THEN '新規'
    ELSE 'リピーター'
  END AS user_type,
  IFNULL(e.collected_traffic_source.manual_medium, '(none)') AS medium,
  COUNT(DISTINCT e.user_pseudo_id) AS users,
  COUNT(DISTINCT
    CONCAT(e.user_pseudo_id, '-',
    CAST((SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS STRING))
  ) AS sessions
FROM `${PROJECT}.${DATASET}.events_*` e
LEFT JOIN first_visit_date f ON e.user_pseudo_id = f.user_pseudo_id
WHERE e._TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  AND e.event_name = 'session_start'
GROUP BY user_type, medium
ORDER BY user_type, sessions DESC
