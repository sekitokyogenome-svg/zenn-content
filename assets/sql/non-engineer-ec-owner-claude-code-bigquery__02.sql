-- 出典: 非エンジニアEC経営者がClaude Code × BigQueryで自走できるようになるまで
-- 記事: articles/non-engineer-ec-owner-claude-code-bigquery.md（体験3：定期的に見たい数字を「型」にする）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 週次ダッシュボードSQL
WITH base AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_date,
    (SELECT value.int_value FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    CONCAT(
      IFNULL(collected_traffic_source.manual_source, '(direct)'),
      ' / ',
      IFNULL(collected_traffic_source.manual_medium, '(none)')
    ) AS channel,
    ecommerce.purchase_revenue AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
)
SELECT
  COUNT(DISTINCT CONCAT(
    user_pseudo_id, CAST(session_id AS STRING))
  ) AS total_sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'purchase'),
    COUNT(DISTINCT CONCAT(
      user_pseudo_id, CAST(session_id AS STRING)))
  ) AS purchase_rate,
  ROUND(AVG(
    CASE WHEN event_name = 'purchase' AND revenue > 0
    THEN revenue END
  ), 0) AS avg_order_value,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'add_to_cart'),
    COUNT(DISTINCT CONCAT(
      user_pseudo_id, CAST(session_id AS STRING)))
  ) AS cart_add_rate
FROM base;
