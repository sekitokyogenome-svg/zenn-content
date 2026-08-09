-- 出典: Claude Codeでクロスチャネルアトリビューション分析を自動化した
-- 記事: articles/claude-code-cross-channel-attribution.md（Step 2：線形モデルを実装する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 線形アトリビューション
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
),
touchpoints AS (
  SELECT
    s.user_pseudo_id,
    s.channel,
    s.session_start,
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
),
linear_attribution AS (
  SELECT
    user_pseudo_id,
    channel,
    touchpoint_order,
    total_touchpoints,
    revenue,
    -- 各タッチポイントに均等配分
    SAFE_DIVIDE(
      MAX(revenue) OVER (PARTITION BY user_pseudo_id),
      total_touchpoints
    ) AS attributed_revenue
  FROM touchpoints
)
SELECT
  channel,
  COUNT(*) AS touchpoints,
  ROUND(SUM(attributed_revenue), 0) AS linear_revenue,
  ROUND(AVG(attributed_revenue), 0) AS avg_attributed_revenue
FROM linear_attribution
GROUP BY channel
ORDER BY linear_revenue DESC;
