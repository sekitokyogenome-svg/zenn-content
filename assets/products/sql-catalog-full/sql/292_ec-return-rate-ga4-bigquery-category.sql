-- 292. ECの返品率をGA4×BigQueryで商品カテゴリ別に分析して原因を特定した（返品率が高いカテゴリの流入元を深掘りする）
-- 用途: 返品率が高いカテゴリの流入元を深掘りする
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH
purchases AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_category') AS item_category,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'order_id') AS order_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name = 'purchase'
),

returns AS (
  SELECT
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'order_id') AS order_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name = 'return_request_complete'
)

SELECT
  p.item_category,
  p.medium,
  p.source,
  COUNT(DISTINCT p.order_id) AS purchase_count,
  COUNT(DISTINCT r.order_id) AS return_count,
  ROUND(
    SAFE_DIVIDE(COUNT(DISTINCT r.order_id), COUNT(DISTINCT p.order_id)) * 100, 2
  ) AS return_rate_pct
FROM
  purchases p
LEFT JOIN
  returns r ON p.order_id = r.order_id
WHERE
  p.item_category IN ('shoes', 'outerwear')   -- 返品率が高いカテゴリに絞る
  AND p.item_category IS NOT NULL
GROUP BY
  p.item_category, p.medium, p.source
ORDER BY
  p.item_category, return_rate_pct DESC
;
