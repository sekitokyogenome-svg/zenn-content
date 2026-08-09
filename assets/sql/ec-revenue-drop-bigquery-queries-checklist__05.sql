-- 出典: EC売上が下がったとき最初に確認すべきBigQueryクエリ5選
-- 記事: articles/ec-revenue-drop-bigquery-queries-checklist.md（クエリ5：ファネルステップ比較（どの段階で離脱が増えたか））
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH funnel AS (
  SELECT
    CASE
      WHEN _TABLE_SUFFIX BETWEEN '20260301' AND '20260328' THEN 'current'
      WHEN _TABLE_SUFFIX BETWEEN '20260201' AND '20260228' THEN 'previous'
    END AS period,
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING
    )) AS session_id,
    event_name
  FROM
    `analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
    AND event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
)
SELECT
  period,
  COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN session_id END) AS view_item_sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN session_id END) AS add_to_cart_sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'begin_checkout' THEN session_id END) AS begin_checkout_sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN session_id END) AS purchase_sessions,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN session_id END),
    COUNT(DISTINCT CASE WHEN event_name = 'view_item' THEN session_id END)
  ) * 100, 2) AS view_to_cart_rate,
  ROUND(SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN session_id END),
    COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart' THEN session_id END)
  ) * 100, 2) AS cart_to_purchase_rate
FROM
  funnel
WHERE
  period IS NOT NULL
GROUP BY
  period
ORDER BY
  period
