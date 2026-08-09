-- 出典: BigQueryでEC受注データ×GA4データを結合して正確な売上帰属分析をする
-- 記事: articles/bigquery-ec-order-ga4-revenue-attribution.md（GA4データと受注データを結合するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH
-- 受注が発生したセッションのGA4情報を取得
ga4_sessions AS (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_source AS traffic_source,
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_campaign_name AS campaign_name,
    MIN(event_timestamp) AS session_start_at
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260131'
    AND event_name = 'session_start'
  GROUP BY
    user_pseudo_id,
    ga_session_id,
    traffic_source,
    traffic_medium,
    campaign_name
),

-- 確定済み受注のみを対象にする
confirmed_orders AS (
  SELECT
    order_id,
    user_pseudo_id,
    ga_session_id,
    order_amount,
    ordered_at
  FROM
    `${PROJECT}.${DATASET}.ec_orders`
  WHERE
    order_status = 'confirmed'
    AND DATE(ordered_at) BETWEEN '2026-01-01' AND '2026-01-31'
)

-- 受注と流入元を結合して集計
SELECT
  COALESCE(s.traffic_source, '(direct)')   AS traffic_source,
  COALESCE(s.traffic_medium, '(none)')     AS traffic_medium,
  COALESCE(s.campaign_name, '(not set)')   AS campaign_name,
  COUNT(o.order_id)                        AS order_count,
  SUM(o.order_amount)                      AS total_revenue,
  ROUND(AVG(o.order_amount), 0)            AS avg_order_value
FROM
  confirmed_orders AS o
LEFT JOIN
  ga4_sessions AS s
  ON  o.user_pseudo_id = s.user_pseudo_id
  AND o.ga_session_id  = s.ga_session_id
GROUP BY
  traffic_source,
  traffic_medium,
  campaign_name
ORDER BY
  total_revenue DESC
