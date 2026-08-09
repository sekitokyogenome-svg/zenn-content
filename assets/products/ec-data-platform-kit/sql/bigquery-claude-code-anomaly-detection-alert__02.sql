-- BigQuery × Claude Codeで異常検知アラートを作る【売上急落を即通知】
-- 用途: 異常検知ロジックのSQL
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH daily_metrics AS (
  SELECT
    event_date,
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, '-',
        (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
      )
    ) AS sessions,
    IFNULL(SUM(ecommerce.purchase_revenue), 0) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
  GROUP BY
    event_date
),

with_moving_avg AS (
  SELECT
    *,
    AVG(sessions) OVER (
      ORDER BY event_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS avg_sessions_7d,
    AVG(revenue) OVER (
      ORDER BY event_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING
    ) AS avg_revenue_7d
  FROM daily_metrics
)

SELECT
  event_date,
  sessions,
  revenue,
  avg_sessions_7d,
  avg_revenue_7d,
  SAFE_DIVIDE(sessions - avg_sessions_7d, avg_sessions_7d) * 100 AS session_deviation_pct,
  SAFE_DIVIDE(revenue - avg_revenue_7d, avg_revenue_7d) * 100 AS revenue_deviation_pct,
  CASE
    WHEN SAFE_DIVIDE(sessions - avg_sessions_7d, avg_sessions_7d) * 100 < -30 THEN TRUE
    WHEN SAFE_DIVIDE(revenue - avg_revenue_7d, avg_revenue_7d) * 100 < -30 THEN TRUE
    ELSE FALSE
  END AS is_anomaly
FROM with_moving_avg
WHERE event_date = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
