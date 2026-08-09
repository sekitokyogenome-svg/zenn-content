-- 出典: GA4×BigQueryでコンバージョン経路を分析するSQL
-- 記事: articles/ga4-bigquery-conversion-path-analysis.md（セッション内のページ遷移パスをSQLで生成する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH session_pages AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    event_timestamp,
    REGEXP_EXTRACT(
      (SELECT value.string_value
       FROM UNNEST(event_params)
       WHERE key = 'page_location'),
      r'https?://[^/]+(/.*)') AS page_path
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
    AND event_name = 'page_view'
)
SELECT
  session_id,
  STRING_AGG(page_path, ' → ' ORDER BY event_timestamp) AS page_path_sequence,
  COUNT(*) AS page_views
FROM session_pages
GROUP BY session_id
ORDER BY page_views DESC
LIMIT 20
