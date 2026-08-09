-- BigQueryでGA4の流入経路×購入金額のヒートマップを作成した
-- 用途: 時間帯×チャネルのクロス集計
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_data AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    CASE
      WHEN collected_traffic_source.manual_medium = 'organic' THEN 'Organic Search'
      WHEN collected_traffic_source.manual_medium = 'cpc' THEN 'Paid Search'
      WHEN collected_traffic_source.manual_medium = 'social' THEN 'Social'
      WHEN collected_traffic_source.manual_medium = 'email' THEN 'Email'
      ELSE 'Other'
    END AS channel,
    -- 日本時間に変換
    EXTRACT(HOUR FROM TIMESTAMP_ADD(TIMESTAMP_MICROS(event_timestamp), INTERVAL 9 HOUR)) AS hour_jst,
    EXTRACT(DAYOFWEEK FROM TIMESTAMP_ADD(TIMESTAMP_MICROS(event_timestamp), INTERVAL 9 HOUR)) AS dow,
    event_name,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
),

session_summary AS (
  SELECT
    user_pseudo_id,
    session_id,
    channel,
    -- 時間帯を4分割
    CASE
      WHEN hour_jst BETWEEN 6 AND 11 THEN '朝(6-11時)'
      WHEN hour_jst BETWEEN 12 AND 17 THEN '昼(12-17時)'
      WHEN hour_jst BETWEEN 18 AND 23 THEN '夜(18-23時)'
      ELSE '深夜(0-5時)'
    END AS time_slot,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    SUM(IF(event_name = 'purchase', revenue, 0)) AS session_revenue
  FROM session_data
  GROUP BY user_pseudo_id, session_id, channel, time_slot
)

SELECT
  channel,
  time_slot,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS purchases,
  ROUND(SUM(session_revenue), 0) AS total_revenue,
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS cvr
FROM session_summary
GROUP BY channel, time_slot
ORDER BY channel, time_slot
