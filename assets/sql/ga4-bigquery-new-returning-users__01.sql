-- 出典: GA4×BigQueryでリピーターと新規ユーザーを分離して分析する
-- 記事: articles/ga4-bigquery-new-returning-users.md（基本パターン：first_visitイベントの有無で判定）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH user_type AS (
  SELECT
    user_pseudo_id,
    MAX(CASE WHEN event_name = 'first_visit' THEN 1 ELSE 0 END) AS is_new_user
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
  GROUP BY user_pseudo_id
)
SELECT
  CASE WHEN is_new_user = 1 THEN '新規' ELSE 'リピーター' END AS user_type,
  COUNT(*) AS users
FROM user_type
GROUP BY user_type
