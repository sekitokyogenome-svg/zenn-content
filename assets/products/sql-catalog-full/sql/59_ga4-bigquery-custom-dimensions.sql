-- 59. GA4×BigQueryでカスタムディメンションを活用した分析（実践例2：会員ランク別の行動分析）
-- 用途: 実践例2：会員ランク別の行動分析
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH user_tier AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'membership_tier') AS membership_tier
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
    AND event_name = 'session_start'
    AND (SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'membership_tier') IS NOT NULL
),

user_events AS (
  SELECT
    e.user_pseudo_id,
    t.membership_tier,
    e.event_name,
    (SELECT value.int_value FROM UNNEST(e.event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `${PROJECT}.${DATASET}.events_*` e
  INNER JOIN user_tier t ON e.user_pseudo_id = t.user_pseudo_id
  WHERE e._TABLE_SUFFIX BETWEEN '20250301' AND '20250331'
)

SELECT
  membership_tier,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS sessions,
  COUNTIF(event_name = 'page_view') AS page_views,
  COUNTIF(event_name = 'add_to_cart') AS add_to_carts,
  COUNTIF(event_name = 'purchase') AS purchases
FROM user_events
GROUP BY membership_tier
ORDER BY users DESC
