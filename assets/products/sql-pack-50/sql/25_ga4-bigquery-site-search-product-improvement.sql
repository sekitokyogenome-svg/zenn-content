-- 25. ECサイトのサイト内検索キーワードをGA4×BigQueryで分析して品揃えを改善した
-- 用途: 検索キーワードごとの購入転換率を算出する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH search_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'search_term') AS search_term
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'view_search_results'
),

purchase_sessions AS (
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
)

SELECT
  ss.search_term,
  COUNT(DISTINCT CONCAT(ss.user_pseudo_id, '-', CAST(ss.session_id AS STRING))) AS search_sessions,
  COUNT(DISTINCT CONCAT(ps.user_pseudo_id, '-', CAST(ps.session_id AS STRING))) AS purchase_sessions,
  ROUND(
    COUNT(DISTINCT CONCAT(ps.user_pseudo_id, '-', CAST(ps.session_id AS STRING)))
    / COUNT(DISTINCT CONCAT(ss.user_pseudo_id, '-', CAST(ss.session_id AS STRING))) * 100,
    2
  ) AS search_to_purchase_rate
FROM search_sessions ss
LEFT JOIN purchase_sessions ps
  ON ss.user_pseudo_id = ps.user_pseudo_id
  AND ss.session_id = ps.session_id
WHERE ss.search_term IS NOT NULL
GROUP BY ss.search_term
HAVING search_sessions >= 5
ORDER BY search_sessions DESC
