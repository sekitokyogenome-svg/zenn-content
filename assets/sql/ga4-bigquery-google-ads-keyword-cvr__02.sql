-- 出典: GA4×BigQueryでGoogle広告のキーワード別CVRを正確に測定する
-- 記事: articles/ga4-bigquery-google-ads-keyword-cvr.md（GA4データからgclidを抽出するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
