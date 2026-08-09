-- GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する
-- 用途: 結合のためのGA4側の準備
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH ga4_landing AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    REGEXP_EXTRACT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
      r'^https?://[^/]+(/.*)$'
    ) AS page_path,
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'entrances') AS is_entrance
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND event_name = 'page_view'
),

ga4_sessions AS (
  SELECT
    event_date,
    page_path,
    COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS users
  FROM ga4_landing
  WHERE is_entrance = 1
  GROUP BY event_date, page_path
)

SELECT * FROM ga4_sessions
