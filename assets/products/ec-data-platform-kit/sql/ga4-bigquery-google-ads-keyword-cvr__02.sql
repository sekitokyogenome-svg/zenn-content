-- GA4×BigQueryでGoogle広告のキーワード別CVRを正確に測定する
-- 用途: GA4データからgclidを抽出するSQL
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH ga4_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    event_name,
    event_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
gclid_extracted AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    REGEXP_EXTRACT(page_location, r'gclid=([^&]+)') AS gclid,
    event_name,
    event_date
  FROM ga4_sessions
  WHERE medium = 'cpc'
    AND source = 'google'
)
SELECT DISTINCT
  user_pseudo_id,
  ga_session_id,
  gclid,
  event_date
FROM gclid_extracted
WHERE gclid IS NOT NULL;
