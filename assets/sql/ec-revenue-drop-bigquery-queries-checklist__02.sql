-- 出典: EC売上が下がったとき最初に確認すべきBigQueryクエリ5選
-- 記事: articles/ec-revenue-drop-bigquery-queries-checklist.md（クエリ2：チャネル別売上比較（どのチャネルが落ちたか））
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH period_data AS (
  SELECT
    CASE
      WHEN _TABLE_SUFFIX BETWEEN '20260301' AND '20260328' THEN 'current'
      WHEN _TABLE_SUFFIX BETWEEN '20260201' AND '20260228' THEN 'previous'
    END AS period,
    collected_traffic_source.manual_medium AS medium,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    user_pseudo_id,
    event_name,
    ecommerce.purchase_revenue,
    ecommerce.transaction_id
  FROM
    `analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
)
SELECT
  period,
  IFNULL(medium, '(none)') AS medium,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN transaction_id END) AS transactions,
  SUM(CASE WHEN event_name = 'purchase' THEN purchase_revenue END) AS revenue
FROM
  period_data
WHERE
  period IS NOT NULL
GROUP BY
  period, medium
ORDER BY
  period, revenue DESC
