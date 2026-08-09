-- 出典: GA4×BigQueryでSearch Consoleデータを結合してオーガニック分析する
-- 記事: articles/ga4-bigquery-search-console-organic.md（GA4 × Search Console結合クエリ）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH ga4_landing AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    REGEXP_EXTRACT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location'),
      r'^https?://[^/]+(/.*)$'
    ) AS page_path,
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'entrances') AS is_entrance,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
),

ga4_by_page AS (
  SELECT
    event_date,
    page_path,
    COUNT(DISTINCT CASE WHEN is_entrance = 1
      THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))
    END) AS organic_sessions,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNTIF(event_name = 'purchase') AS purchases
  FROM ga4_landing
  GROUP BY event_date, page_path
),

gsc AS (
  SELECT
    data_date AS event_date,
    REGEXP_EXTRACT(url, r'^https?://[^/]+(/.*)') AS page_path,
    SUM(impressions) AS impressions,
    SUM(clicks) AS clicks,
    ROUND(SAFE_DIVIDE(SUM(sum_position), SUM(impressions)), 1) AS avg_position
  FROM `your-project.searchconsole.searchdata_url_impression`
  WHERE data_date BETWEEN '2025-03-01' AND '2025-03-31'
  GROUP BY event_date, page_path
)

SELECT
  COALESCE(ga.page_path, gsc.page_path) AS page_path,
  SUM(gsc.impressions) AS search_impressions,
  SUM(gsc.clicks) AS search_clicks,
  ROUND(SAFE_DIVIDE(SUM(gsc.clicks), SUM(gsc.impressions)) * 100, 2) AS ctr_pct,
  ROUND(AVG(gsc.avg_position), 1) AS avg_position,
  SUM(ga.organic_sessions) AS site_sessions,
  SUM(ga.purchases) AS purchases,
  ROUND(SAFE_DIVIDE(SUM(ga.purchases), SUM(ga.organic_sessions)) * 100, 2) AS cvr_pct
FROM gsc
LEFT JOIN ga4_by_page ga
  ON gsc.event_date = ga.event_date
  AND gsc.page_path = ga.page_path
GROUP BY page_path
HAVING search_clicks >= 5
ORDER BY search_clicks DESC
LIMIT 30
