-- 出典: BigQueryでGA4の日次・週次・月次集計テーブルをスケジュール実行する
-- 記事: articles/bigquery-ga4-scheduled-aggregation-tables.md（月次集計テーブルの設計）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 毎月1日に実行：前月分の月次集計
DECLARE month_start DATE DEFAULT DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH);
DECLARE month_end DATE DEFAULT LAST_DAY(month_start);

CREATE TABLE IF NOT EXISTS `your-project.mart.mart_monthly_summary` (
  month_start_date DATE,
  medium STRING,
  sessions INT64,
  users INT64,
  new_users INT64,
  purchases INT64,
  cvr_pct FLOAT64
)
PARTITION BY month_start_date
CLUSTER BY medium;

MERGE `your-project.mart.mart_monthly_summary` AS target
USING (
  SELECT
    month_start AS month_start_date,
    IFNULL(collected_traffic_source.manual_medium, '(none)') AS medium,
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
    ) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNT(DISTINCT CASE WHEN event_name = 'first_visit' THEN user_pseudo_id END) AS new_users,
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
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', month_start) AND FORMAT_DATE('%Y%m%d', month_end)
    AND event_name IN ('session_start', 'page_view', 'purchase', 'first_visit')
  GROUP BY medium
) AS source
ON target.month_start_date = source.month_start_date
  AND target.medium = source.medium
WHEN MATCHED THEN
  UPDATE SET
    sessions = source.sessions,
    users = source.users,
    new_users = source.new_users,
    purchases = source.purchases,
    cvr_pct = source.cvr_pct
WHEN NOT MATCHED THEN
  INSERT (month_start_date, medium, sessions, users, new_users, purchases, cvr_pct)
  VALUES (source.month_start_date, source.medium, source.sessions, source.users, source.new_users, source.purchases, source.cvr_pct)
