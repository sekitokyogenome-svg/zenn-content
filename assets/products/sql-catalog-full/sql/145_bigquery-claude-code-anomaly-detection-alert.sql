-- 145. BigQuery × Claude Codeで異常検知アラートを作る【売上急落を即通知】（日次メトリクスと移動平均のSQL）
-- 用途: 日次メトリクスと移動平均のSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH daily_metrics AS (
  SELECT
    event_date,
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, '-',
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      )
    ) AS sessions,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
  GROUP BY
    event_date
)

SELECT
  event_date,
  sessions,
  revenue,
  AVG(sessions) OVER (
    ORDER BY event_date
    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
  ) AS avg_sessions_7d,
  AVG(revenue) OVER (
    ORDER BY event_date
    ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
  ) AS avg_revenue_7d
FROM daily_metrics
ORDER BY event_date DESC
