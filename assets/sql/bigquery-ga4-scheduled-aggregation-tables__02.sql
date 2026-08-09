-- 出典: BigQueryでGA4の日次・週次・月次集計テーブルをスケジュール実行する
-- 記事: articles/bigquery-ga4-scheduled-aggregation-tables.md（週次集計テーブルの設計）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 毎週月曜日に実行：前週分の週次集計
DECLARE week_start DATE DEFAULT DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY), WEEK(MONDAY));
DECLARE week_end DATE DEFAULT DATE_ADD(week_start, INTERVAL 6 DAY);

CREATE TABLE IF NOT EXISTS `your-project.mart.mart_weekly_summary` (
  week_start_date DATE,
  medium STRING,
  sessions INT64,
  users INT64,
  purchases INT64,
  cvr_pct FLOAT64
)
PARTITION BY week_start_date
CLUSTER BY medium;

MERGE `your-project.mart.mart_weekly_summary` AS target
USING (
  SELECT
    week_start AS week_start_date,
    IFNULL(collected_traffic_source.manual_medium, '(none)') AS medium,
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
    ) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS users,
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
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', week_start) AND FORMAT_DATE('%Y%m%d', week_end)
    AND event_name IN ('session_start', 'page_view', 'purchase')
  GROUP BY medium
) AS source
ON target.week_start_date = source.week_start_date
  AND target.medium = source.medium
WHEN MATCHED THEN
  UPDATE SET
    sessions = source.sessions,
    users = source.users,
    purchases = source.purchases,
    cvr_pct = source.cvr_pct
WHEN NOT MATCHED THEN
  INSERT (week_start_date, medium, sessions, users, purchases, cvr_pct)
  VALUES (source.week_start_date, source.medium, source.sessions, source.users, source.purchases, source.cvr_pct)
