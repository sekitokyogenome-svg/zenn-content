-- 出典: GA4×BigQueryでリピーターと新規ユーザーを分離して分析する
-- 記事: articles/ga4-bigquery-new-returning-users.md（応用パターン：初回訪問日を特定して分類する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH first_visit_date AS (
  SELECT
    user_pseudo_id,
    MIN(PARSE_DATE('%Y%m%d', event_date)) AS first_visit_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
),

target_users AS (
  SELECT DISTINCT
    user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
)

SELECT
  CASE
    WHEN f.first_visit_date BETWEEN '2025-03-01' AND '2025-03-31'
    THEN '新規'
    ELSE 'リピーター'
  END AS user_type,
  COUNT(DISTINCT t.user_pseudo_id) AS users
FROM target_users t
LEFT JOIN first_visit_date f ON t.user_pseudo_id = f.user_pseudo_id
GROUP BY user_type
