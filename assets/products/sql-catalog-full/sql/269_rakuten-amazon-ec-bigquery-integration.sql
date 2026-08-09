-- 269. 楽天・Amazon・自社ECの売上データをBigQueryに集約して一元管理する方法（GA4データと売上を紐づける分析クエリ）
-- 用途: GA4データと売上を紐づける分析クエリ
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH sessions AS (
  SELECT
    -- ga_session_id は event_params 経由で取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    )                                                          AS ga_session_id,
    user_pseudo_id,
    -- 流入元は collected_traffic_source を参照
    collected_traffic_source.manual_medium                     AS medium,
    collected_traffic_source.manual_source                     AS source,
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')      AS session_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'session_start'
),

purchases AS (
  SELECT
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    )                                                          AS ga_session_id,
    user_pseudo_id,
    event_value_in_usd                                         AS purchase_value
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
)

SELECT
  s.medium,
  s.source,
  COUNT(DISTINCT s.ga_session_id)  AS sessions,
  COUNT(DISTINCT p.ga_session_id)  AS converting_sessions,
  ROUND(SUM(p.purchase_value), 0)  AS total_revenue_usd
FROM sessions AS s
LEFT JOIN purchases AS p
  ON s.ga_session_id  = p.ga_session_id
 AND s.user_pseudo_id = p.user_pseudo_id
GROUP BY s.medium, s.source
ORDER BY total_revenue_usd DESC;
