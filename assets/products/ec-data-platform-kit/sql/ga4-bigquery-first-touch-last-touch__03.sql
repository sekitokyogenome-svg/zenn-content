-- GA4×BigQueryでユーザーのファーストタッチ・ラストタッチを取得する
-- 用途: ファーストタッチとラストタッチを並べて比較する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH sessions AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_source AS session_source,
    collected_traffic_source.manual_medium AS session_medium
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_source IS NOT NULL
),

converters AS (
  SELECT DISTINCT user_pseudo_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
),

attribution AS (
  SELECT DISTINCT
    s.user_pseudo_id,
    FIRST_VALUE(s.session_source) OVER w AS first_touch_source,
    FIRST_VALUE(s.session_medium) OVER w AS first_touch_medium,
    LAST_VALUE(s.session_source) OVER w AS last_touch_source,
    LAST_VALUE(s.session_medium) OVER w AS last_touch_medium
  FROM sessions s
  INNER JOIN converters c ON s.user_pseudo_id = c.user_pseudo_id
  WINDOW w AS (
    PARTITION BY s.user_pseudo_id
    ORDER BY s.event_timestamp
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
  )
)

SELECT
  first_touch_source,
  first_touch_medium,
  last_touch_source,
  last_touch_medium,
  COUNT(DISTINCT user_pseudo_id) AS converting_users
FROM attribution
GROUP BY 1, 2, 3, 4
ORDER BY converting_users DESC
LIMIT 30
