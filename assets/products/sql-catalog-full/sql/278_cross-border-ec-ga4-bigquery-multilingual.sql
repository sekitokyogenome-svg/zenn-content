-- 278. 越境ECのGA4多言語計測をBigQueryで国別に正確に集計する方法（流入元と購買行動を国別に分析するSQL）
-- 用途: 流入元と購買行動を国別に分析するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH purchase_events AS (
  SELECT
    user_pseudo_id,
    geo.country AS country,
    device.language AS browser_language,
    collected_traffic_source.manual_source AS utm_source,
    collected_traffic_source.manual_medium AS utm_medium,
    ecommerce.purchase_revenue AS revenue,
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
    AND event_name = 'purchase'
)

SELECT
  country,
  browser_language,
  COALESCE(utm_medium, '(none)') AS medium,
  COALESCE(utm_source, '(direct)') AS source,
  COUNT(*) AS purchase_count,
  ROUND(SUM(revenue), 2) AS total_revenue,
  ROUND(AVG(revenue), 2) AS avg_order_value
FROM
  purchase_events
GROUP BY
  country,
  browser_language,
  medium,
  source
HAVING
  purchase_count >= 3
ORDER BY
  total_revenue DESC;
