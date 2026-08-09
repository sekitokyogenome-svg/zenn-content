-- 140. Claude Codeでクロスチャネルアトリビューション分析を自動化した（Step 1：ユーザーのタッチポイント経路を抽出する）
-- 用途: Step 1：ユーザーのタッチポイント経路を抽出する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH user_sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    PARSE_TIMESTAMP(
      '%Y%m%d%H%M%S',
      CONCAT(event_date, LPAD(
        CAST(EXTRACT(HOUR FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0'),
        LPAD(
        CAST(EXTRACT(MINUTE FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0'),
        LPAD(
        CAST(EXTRACT(SECOND FROM TIMESTAMP_MICROS(event_timestamp)) AS STRING),
        2, '0')
      )
    ) AS session_start,
    CONCAT(
      IFNULL(collected_traffic_source.manual_source, '(direct)'),
      ' / ',
      IFNULL(collected_traffic_source.manual_medium, '(none)')
    ) AS channel,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260201' AND '20260331'
  GROUP BY user_pseudo_id, session_id, session_start, channel
),
converting_users AS (
  SELECT user_pseudo_id
  FROM user_sessions
  WHERE has_purchase = 1
)
SELECT
  s.user_pseudo_id,
  s.channel,
  s.session_start,
  s.has_purchase,
  s.revenue,
  ROW_NUMBER() OVER (
    PARTITION BY s.user_pseudo_id
    ORDER BY s.session_start
  ) AS touchpoint_order,
  COUNT(*) OVER (
    PARTITION BY s.user_pseudo_id
  ) AS total_touchpoints
FROM user_sessions s
INNER JOIN converting_users c
  ON s.user_pseudo_id = c.user_pseudo_id
ORDER BY s.user_pseudo_id, s.session_start;
