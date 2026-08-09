-- 252. ECサイトのサイト内検索キーワードをGA4×BigQueryで分析して品揃えを改善した（検索キーワードのランキングを取得する）
-- 用途: 検索キーワードのランキングを取得する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'search_term') AS search_term,
  COUNT(*) AS search_count,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
  AND event_name = 'view_search_results'
GROUP BY search_term
HAVING search_term IS NOT NULL
ORDER BY search_count DESC
LIMIT 50
