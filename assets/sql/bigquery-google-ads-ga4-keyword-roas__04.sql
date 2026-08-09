-- 出典: BigQueryでGoogle広告×GA4データを結合してキーワード別の真のROASを計算する
-- 記事: articles/bigquery-google-ads-ga4-keyword-roas.md（Google広告データと結合してキーワード別ROASを算出するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH ga4_raw AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_medium  AS medium,
    collected_traffic_source.manual_source  AS source,
    collected_traffic_source.manual_term    AS keyword,
    event_date,
    event_name,
    ecommerce.purchase_revenue              AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
),

paid_search_sessions AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MAX(keyword) AS keyword
  FROM ga4_raw
  WHERE
    medium = 'cpc'
    AND source = 'google'
    AND keyword IS NOT NULL
  GROUP BY
    user_pseudo_id,
    ga_session_id
),

session_revenue AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    SUM(revenue) AS session_revenue
  FROM ga4_raw
  WHERE event_name = 'purchase'
  GROUP BY
    user_pseudo_id,
    ga_session_id
),

keyword_ga4 AS (
  SELECT
    LOWER(TRIM(s.keyword)) AS keyword_normalized,
    COUNT(DISTINCT CONCAT(s.user_pseudo_id, CAST(s.ga_session_id AS STRING))) AS sessions,
    COALESCE(SUM(sr.session_revenue), 0) AS revenue
  FROM paid_search_sessions s
  LEFT JOIN session_revenue sr
    ON s.user_pseudo_id = sr.user_pseudo_id
    AND s.ga_session_id = sr.ga_session_id
  GROUP BY
    keyword_normalized
),

keyword_ads AS (
  SELECT
    LOWER(TRIM(keyword_text)) AS keyword_normalized,
    SUM(cost)                 AS cost,
    SUM(clicks)               AS clicks,
    SUM(impressions)          AS impressions
  FROM
    `your_project.ads_data.keyword_stats`
  WHERE
    date BETWEEN '2025-06-01' AND '2025-06-30'
  GROUP BY
    keyword_normalized
)

-- 結合してROASを算出
SELECT
  COALESCE(g.keyword_normalized, a.keyword_normalized) AS keyword,
  COALESCE(a.cost, 0)         AS cost,
  COALESCE(a.clicks, 0)       AS clicks,
  COALESCE(a.impressions, 0)  AS impressions,
  COALESCE(g.sessions, 0)     AS ga4_sessions,
  COALESCE(g.revenue, 0)      AS ga4_revenue,
  CASE
    WHEN COALESCE(a.cost, 0) = 0 THEN NULL
    ELSE ROUND(COALESCE(g.revenue, 0) / a.cost, 2)
  END AS roas
FROM keyword_ga4 g
FULL OUTER JOIN keyword_ads a
  ON g.keyword_normalized = a.keyword_normalized
ORDER BY
  ga4_revenue DESC;
