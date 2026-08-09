-- BigQuery × Looker Studioで前年同期比グラフを作る方法
-- 用途: 基本パターン: 日別の売上を今年・前年で横並びにする
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH current_year AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    SUM(ecommerce.purchase_revenue) AS revenue,
    COUNTIF(event_name = 'purchase') AS purchases,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_TRUNC(CURRENT_DATE(), MONTH))
      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  GROUP BY date
),

previous_year AS (
  SELECT
    DATE_ADD(PARSE_DATE('%Y%m%d', event_date), INTERVAL 1 YEAR) AS date,
    SUM(ecommerce.purchase_revenue) AS revenue_ly,
    COUNTIF(event_name = 'purchase') AS purchases_ly,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions_ly
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 1 YEAR))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 YEAR))
  GROUP BY date
)

SELECT
  c.date,
  c.revenue AS revenue_current,
  p.revenue_ly AS revenue_previous,
  c.sessions AS sessions_current,
  p.sessions_ly AS sessions_previous,
  SAFE_DIVIDE(c.revenue - p.revenue_ly, p.revenue_ly) * 100 AS revenue_yoy_pct,
  SAFE_DIVIDE(c.sessions - p.sessions_ly, p.sessions_ly) * 100 AS sessions_yoy_pct
FROM
  current_year c
LEFT JOIN
  previous_year p ON c.date = p.date
ORDER BY
  c.date
