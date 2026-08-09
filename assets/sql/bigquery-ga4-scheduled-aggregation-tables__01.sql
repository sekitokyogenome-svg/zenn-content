-- 出典: BigQueryでGA4の日次・週次・月次集計テーブルをスケジュール実行する
-- 記事: articles/bigquery-ga4-scheduled-aggregation-tables.md（日次セッション集計）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 日次実行：前日分のセッション集計をmart_daily_sessionsに追記
DECLARE target_date STRING DEFAULT FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY));

CREATE TABLE IF NOT EXISTS `your-project.mart.mart_daily_sessions` (
  event_date DATE,
  medium STRING,
  device_category STRING,
  sessions INT64,
  users INT64,
  page_views INT64,
  purchases INT64,
  cvr_pct FLOAT64
)
PARTITION BY event_date
CLUSTER BY medium, device_category;

MERGE `your-project.mart.mart_daily_sessions` AS target
USING (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    IFNULL(collected_traffic_source.manual_medium, '(none)') AS medium,
    device.category AS device_category,
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
    ) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNTIF(event_name = 'page_view') AS page_views,
    COUNTIF(event_name = 'purchase') AS purchases,
    ROUND(
      SAFE_DIVIDE(
        COUNTIF(event_name = 'purchase'),
        COUNT(DISTINCT
          CONCAT(user_pseudo_id, '-',
          CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
        )
      ) * 100, 2
    ) AS cvr_pct
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX = target_date
    AND event_name IN ('session_start', 'page_view', 'purchase')
  GROUP BY event_date, medium, device_category
) AS source
ON target.event_date = source.event_date
  AND target.medium = source.medium
  AND target.device_category = source.device_category
WHEN MATCHED THEN
  UPDATE SET
    sessions = source.sessions,
    users = source.users,
    page_views = source.page_views,
    purchases = source.purchases,
    cvr_pct = source.cvr_pct
WHEN NOT MATCHED THEN
  INSERT (event_date, medium, device_category, sessions, users, page_views, purchases, cvr_pct)
  VALUES (source.event_date, source.medium, source.device_category, source.sessions, source.users, source.page_views, source.purchases, source.cvr_pct)
