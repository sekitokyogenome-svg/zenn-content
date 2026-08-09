-- 出典: BigQueryで1回しか買わない顧客と2回以上買う顧客の行動差を分析した
-- 記事: articles/bigquery-one-time-vs-repeat-buyer-analysis.md（流入元の違いを確認する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH purchase_counts AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

buyer_type AS (
  SELECT
    user_pseudo_id,
    CASE WHEN purchase_count = 1 THEN 'one_time' ELSE 'repeat' END AS buyer_type
  FROM purchase_counts
),

first_touch AS (
  SELECT
    e.user_pseudo_id,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_medium AS medium,
    ROW_NUMBER() OVER(PARTITION BY e.user_pseudo_id ORDER BY e.event_timestamp) AS rn
  FROM `${PROJECT}.${DATASET}.events_*` e
  INNER JOIN buyer_type bt ON e.user_pseudo_id = bt.user_pseudo_id
  WHERE e._TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND e.event_name = 'session_start'
)

SELECT
  bt.buyer_type,
  ft.source,
  ft.medium,
  COUNT(*) AS users
FROM first_touch ft
INNER JOIN buyer_type bt ON ft.user_pseudo_id = bt.user_pseudo_id
WHERE ft.rn = 1
GROUP BY bt.buyer_type, ft.source, ft.medium
ORDER BY bt.buyer_type, users DESC
