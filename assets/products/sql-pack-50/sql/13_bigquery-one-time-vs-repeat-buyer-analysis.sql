-- 13. BigQueryで1回しか買わない顧客と2回以上買う顧客の行動差を分析した（初回セッションの行動指標を比較する）
-- 用途: 初回セッションの行動指標を比較する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH purchase_counts AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

buyer_type AS (
  SELECT
    user_pseudo_id,
    CASE WHEN purchase_count = 1 THEN 'one_time' ELSE 'repeat' END AS buyer_type
  FROM purchase_counts
),

first_sessions AS (
  SELECT
    e.user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS session_id,
    e.event_name,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'engagement_time_msec') AS engagement_time_msec,
    ROW_NUMBER() OVER(
      PARTITION BY e.user_pseudo_id
      ORDER BY e.event_timestamp
    ) AS event_seq
  FROM `${PROJECT}.${DATASET}.events_*` e
  INNER JOIN buyer_type bt ON e.user_pseudo_id = bt.user_pseudo_id
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
),

first_session_ids AS (
  SELECT DISTINCT user_pseudo_id, session_id
  FROM first_sessions
  WHERE event_seq = 1
),

first_session_metrics AS (
  SELECT
    fs.user_pseudo_id,
    fsi.session_id,
    COUNTIF(fs.event_name = 'page_view') AS page_views,
    SUM(fs.engagement_time_msec) / 1000 AS engagement_sec,
    MAX(IF(fs.event_name = 'add_to_cart', 1, 0)) AS has_add_to_cart,
    MAX(IF(fs.event_name = 'view_item', 1, 0)) AS has_view_item
  FROM first_sessions fs
  INNER JOIN first_session_ids fsi
    ON fs.user_pseudo_id = fsi.user_pseudo_id
    AND fs.session_id = fsi.session_id
  GROUP BY fs.user_pseudo_id, fsi.session_id
)

SELECT
  bt.buyer_type,
  COUNT(*) AS users,
  ROUND(AVG(fsm.page_views), 1) AS avg_page_views,
  ROUND(AVG(fsm.engagement_sec), 1) AS avg_engagement_sec,
  ROUND(COUNTIF(fsm.has_view_item = 1) / COUNT(*) * 100, 1) AS view_item_rate,
  ROUND(COUNTIF(fsm.has_add_to_cart = 1) / COUNT(*) * 100, 1) AS add_to_cart_rate
FROM first_session_metrics fsm
INNER JOIN buyer_type bt ON fsm.user_pseudo_id = bt.user_pseudo_id
GROUP BY bt.buyer_type
