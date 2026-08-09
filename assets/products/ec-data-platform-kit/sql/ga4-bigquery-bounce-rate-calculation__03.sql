-- BigQueryでGA4の直帰率を正確に計算する方法（GA4に直帰率はない問題）
-- 用途: 方法2：engagement_time_msecを使う
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_metrics AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    SUM(
      IFNULL(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'engagement_time_msec'), 0)
    ) AS total_engagement_time_msec,
    COUNTIF(event_name = 'page_view') AS page_views
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  GROUP BY session_id
)
SELECT
  COUNT(*) AS total_sessions,
  COUNTIF(
    total_engagement_time_msec < 10000
    AND page_views <= 1
  ) AS bounced_sessions,
  ROUND(
    COUNTIF(
      total_engagement_time_msec < 10000
      AND page_views <= 1
    ) / COUNT(*) * 100, 2
  ) AS bounce_rate_percent
FROM session_metrics
