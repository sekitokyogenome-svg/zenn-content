-- 73. GA4×BigQueryでコンバージョン経路を分析するSQL（セッション内のページ遷移パスをSQLで生成する）
-- 用途: セッション内のページ遷移パスをSQLで生成する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
