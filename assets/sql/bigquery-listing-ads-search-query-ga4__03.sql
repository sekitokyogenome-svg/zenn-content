-- 出典: BigQueryでリスティング広告の検索クエリとGA4行動データを突合分析する
-- 記事: articles/bigquery-listing-ads-search-query-ga4.md（分析視点：クエリごとのサイト行動をどう読むか）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_location'
  ) AS page_location,
  COUNT(*) AS view_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'page_view'
  AND collected_traffic_source.manual_medium = 'cpc'
  AND CONCAT(user_pseudo_id, CAST(
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS STRING
  )) IN (
    -- 購入セッションのIDリスト（サブクエリやWITH句で生成）
    SELECT DISTINCT
      CONCAT(user_pseudo_id, CAST(
        (
          SELECT value.int_value
          FROM UNNEST(event_params)
          WHERE key = 'ga_session_id'
        ) AS STRING
      ))
    FROM
      `${PROJECT}.${DATASET}.events_*`
    WHERE
      _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
      AND event_name = 'purchase'
  )
GROUP BY page_location
ORDER BY view_count DESC
