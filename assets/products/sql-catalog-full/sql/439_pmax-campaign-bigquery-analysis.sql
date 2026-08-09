-- 439. P-MAXキャンペーンの配信実績をBigQueryで詳細分析する方法（エンゲージメント率でセッション品質を評価する）
-- 用途: エンゲージメント率でセッション品質を評価する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_data AS (
  SELECT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')       AS session_id,
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'session_engaged')     AS engaged,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_source = 'google'
    AND collected_traffic_source.manual_medium = 'cpc'
)

SELECT
  source,
  medium,
  COUNT(DISTINCT session_id)                                        AS total_sessions,
  COUNTIF(engaged = '1')                                            AS engaged_sessions,
  ROUND(
    COUNTIF(engaged = '1') / COUNT(DISTINCT session_id) * 100, 1
  )                                                                 AS engagement_rate_pct
FROM session_data
GROUP BY source, medium
ORDER BY total_sessions DESC
