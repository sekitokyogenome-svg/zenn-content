-- BigQueryでリスティング広告の検索クエリとGA4行動データを突合分析する
-- 用途: Google広告の検索クエリデータと突合する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH ga4_sessions AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_term AS keyword,
    event_name,
    (
      SELECT value.string_value
      FROM UNNEST(event_params)
      WHERE key = 'page_location'
    ) AS page_location,
    DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND collected_traffic_source.manual_medium = 'cpc'
),

ads_queries AS (
  SELECT
    Query AS search_query,
    Clicks,
    Cost,
    Conversions,
    Date AS query_date
  FROM
    `your_project.google_ads_export.SearchQueryPerformance`
  WHERE
    Date BETWEEN '2025-06-01' AND '2025-06-30'
)

SELECT
  aq.search_query,
  aq.Clicks,
  aq.Cost,
  aq.Conversions,
  COUNT(DISTINCT CONCAT(gs.user_pseudo_id, CAST(gs.ga_session_id AS STRING))) AS ga4_sessions,
  COUNTIF(gs.event_name = 'purchase') AS purchase_events,
  COUNTIF(gs.event_name = 'generate_lead') AS lead_events
FROM
  ads_queries aq
LEFT JOIN
  ga4_sessions gs
  ON aq.search_query = gs.keyword
  AND aq.query_date = gs.event_date
GROUP BY
  aq.search_query, aq.Clicks, aq.Cost, aq.Conversions
ORDER BY
  aq.Cost DESC
LIMIT 100
