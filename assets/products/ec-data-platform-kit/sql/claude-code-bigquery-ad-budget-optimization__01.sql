-- Claude Code × BigQueryでEC広告の予算配分を自動最適化する提案ツールを作った
-- 用途: GA4データから売上を抽出するSQL
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH channel_revenue AS (
  SELECT
    CONCAT(
      IFNULL(collected_traffic_source.manual_source, '(direct)'),
      ' / ',
      IFNULL(collected_traffic_source.manual_medium, '(none)')
    ) AS channel,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase'
      THEN CONCAT(
        user_pseudo_id,
        CAST((SELECT value.int_value FROM UNNEST(event_params)
              WHERE key = 'ga_session_id') AS STRING)
      ) END) AS conversions,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params)
            WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(
      DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(
      DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
  GROUP BY channel
)
SELECT
  channel,
  sessions,
  conversions,
  revenue,
  SAFE_DIVIDE(conversions, sessions) * 100 AS cvr,
  SAFE_DIVIDE(revenue, sessions) AS revenue_per_session
FROM channel_revenue
ORDER BY revenue DESC;
