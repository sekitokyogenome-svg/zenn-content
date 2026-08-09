-- GA4×BigQueryでユーザーのファーストタッチ・ラストタッチを取得する
-- 用途: ファーストタッチを取得するSQL
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
),

first_touch AS (
  SELECT DISTINCT
    user_pseudo_id,
    FIRST_VALUE(session_source) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY event_timestamp
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_touch_source,
    FIRST_VALUE(session_medium) OVER (
      PARTITION BY user_pseudo_id
      ORDER BY event_timestamp
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_touch_medium
  FROM sessions
  WHERE session_source IS NOT NULL
)

SELECT
  IFNULL(first_touch_source, '(direct)') AS first_touch_source,
  IFNULL(first_touch_medium, '(none)') AS first_touch_medium,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM first_touch
GROUP BY first_touch_source, first_touch_medium
ORDER BY users DESC
LIMIT 20
