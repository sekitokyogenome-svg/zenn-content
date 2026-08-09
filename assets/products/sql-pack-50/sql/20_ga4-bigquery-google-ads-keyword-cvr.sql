-- 20. GA4×BigQueryでGoogle広告のキーワード別CVRを正確に測定する
-- 用途: キーワード別CVRを算出するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH ga4_gclid AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    REGEXP_EXTRACT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
      r'gclid=([^&]+)'
    ) AS gclid,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
    AND collected_traffic_source.manual_medium = 'cpc'
    AND collected_traffic_source.manual_source = 'google'
),
sessions AS (
  SELECT DISTINCT
    user_pseudo_id,
    ga_session_id,
    gclid
  FROM ga4_gclid
  WHERE gclid IS NOT NULL
),
conversions AS (
  SELECT DISTINCT
    user_pseudo_id,
    ga_session_id
  FROM ga4_gclid
  WHERE event_name = 'purchase'
),
keyword_sessions AS (
  SELECT
    ak.keyword,
    ak.match_type,
    ak.campaign_name,
    s.user_pseudo_id,
    s.ga_session_id,
    CASE WHEN c.ga_session_id IS NOT NULL THEN 1 ELSE 0 END AS is_cv
  FROM sessions s
  JOIN `${PROJECT}.${DATASET}.ads_click_keyword` ak
    ON s.gclid = ak.gclid
  LEFT JOIN conversions c
    ON s.user_pseudo_id = c.user_pseudo_id
    AND s.ga_session_id = c.ga_session_id
)
SELECT
  keyword,
  match_type,
  campaign_name,
  COUNT(*) AS sessions,
  SUM(is_cv) AS conversions,
  ROUND(SUM(is_cv) / COUNT(*) * 100, 2) AS cvr
FROM keyword_sessions
GROUP BY keyword, match_type, campaign_name
HAVING sessions >= 5
ORDER BY sessions DESC;
