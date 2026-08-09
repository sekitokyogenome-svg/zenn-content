-- 432. BigQueryでGoogle広告×GA4データを結合してキーワード別の真のROASを計算する（GA4側でキーワード別売上を集計するSQL）
-- 用途: GA4側でキーワード別売上を集計するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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

-- cpcかつgoogle流入のセッションに絞る
paid_search_sessions AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MAX(keyword)    AS keyword,
    MAX(event_date) AS event_date
  FROM ga4_raw
  WHERE
    medium = 'cpc'
    AND source = 'google'
    AND keyword IS NOT NULL
  GROUP BY
    user_pseudo_id,
    ga_session_id
),

-- purchaseイベントの売上をセッションに紐づける
session_revenue AS (
  SELECT
    r.user_pseudo_id,
    r.ga_session_id,
    SUM(r.revenue) AS session_revenue
  FROM ga4_raw r
  WHERE r.event_name = 'purchase'
  GROUP BY
    r.user_pseudo_id,
    r.ga_session_id
),

-- キーワード別に集計
keyword_ga4 AS (
  SELECT
    s.keyword,
    COUNT(DISTINCT CONCAT(s.user_pseudo_id, CAST(s.ga_session_id AS STRING))) AS sessions,
    COALESCE(SUM(sr.session_revenue), 0) AS revenue
  FROM paid_search_sessions s
  LEFT JOIN session_revenue sr
    ON s.user_pseudo_id = sr.user_pseudo_id
    AND s.ga_session_id = sr.ga_session_id
  GROUP BY
    s.keyword
)

SELECT * FROM keyword_ga4
ORDER BY revenue DESC;
