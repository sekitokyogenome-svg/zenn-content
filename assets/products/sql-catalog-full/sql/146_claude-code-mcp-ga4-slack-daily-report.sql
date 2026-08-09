-- 146. Claude Code × MCPでGA4レポートを毎朝Slack通知する仕組みを作った
-- 用途: 日次レポート用SQLクエリ
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH yesterday AS (
  SELECT
    session_default_channel_group AS channel,
    COUNT(DISTINCT session_id) AS sessions,
    COUNTIF(has_purchase = TRUE) AS conversions,
    SUM(purchase_revenue) AS revenue
  FROM `your_project.your_dataset_staging.stg_sessions`
  WHERE session_date = DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY)
  GROUP BY channel
),
day_before AS (
  SELECT
    session_default_channel_group AS channel,
    COUNT(DISTINCT session_id) AS sessions,
    COUNTIF(has_purchase = TRUE) AS conversions,
    SUM(purchase_revenue) AS revenue
  FROM `your_project.your_dataset_staging.stg_sessions`
  WHERE session_date = DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 2 DAY)
  GROUP BY channel
)
SELECT
  y.channel,
  y.sessions,
  y.conversions,
  y.revenue,
  SAFE_DIVIDE(y.sessions - d.sessions, d.sessions) * 100 AS sessions_change_pct,
  SAFE_DIVIDE(y.conversions - d.conversions, d.conversions) * 100 AS conversions_change_pct
FROM yesterday y
LEFT JOIN day_before d USING (channel)
ORDER BY y.sessions DESC
