-- 454. BigQueryでリスティング広告の検索クエリとGA4行動データを突合分析する（GA4テーブルから流入クエリとセッション行動を抽出する）
-- 用途: GA4テーブルから流入クエリとセッション行動を抽出する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_source AS traffic_source,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_term AS keyword,
  event_name,
  event_timestamp,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_location'
  ) AS page_location
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND collected_traffic_source.manual_medium = 'cpc'
  AND event_name IN ('page_view', 'purchase', 'generate_lead')
