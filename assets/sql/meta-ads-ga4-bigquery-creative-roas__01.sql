-- 出典: Meta広告×GA4×BigQueryでクリエイティブ別ROASを深掘りする
-- 記事: articles/meta-ads-ga4-bigquery-creative-roas.md（GA4×BigQueryでUTMパラメータを取得するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH ad_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign') AS campaign,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'content') AS content,
    event_name,
    event_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
    AND collected_traffic_source.manual_source = 'facebook'
    AND collected_traffic_source.manual_medium = 'paid_social'
)
SELECT DISTINCT
  user_pseudo_id,
  ga_session_id,
  campaign,
  content AS creative_name,
  event_date
FROM ad_sessions
WHERE content IS NOT NULL;
