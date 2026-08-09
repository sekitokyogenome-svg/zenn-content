-- 331. GA4×GTMでサイト内検索キーワードを正しく計測する設定（検索キーワードランキング）
-- 用途: 検索キーワードランキング
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  (SELECT value.string_value
   FROM UNNEST(event_params) WHERE key = 'search_term') AS search_term,
  COUNT(*) AS search_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'view_search_results'
  AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
GROUP BY
  search_term
ORDER BY
  search_count DESC
LIMIT 50
