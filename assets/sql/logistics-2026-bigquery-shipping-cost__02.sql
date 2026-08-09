-- 出典: 2024年問題に備えるデータ基盤―配送コストをBigQueryで最適化する
-- 記事: articles/logistics-2026-bigquery-shipping-cost.md（流入経路別・配送コスト分析のSQLサンプル）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 流入経路別の配送コスト集計（GA4と配送データのJOIN例）
WITH ga4_purchases AS (
  SELECT
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'transaction_id'
    ) AS transaction_id,
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_source AS traffic_source,
    ecommerce.purchase_revenue             AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260101' AND '20260731'
    AND event_name = 'purchase'
)
SELECT
  COALESCE(g.traffic_medium, '(none)')       AS medium,
  COALESCE(g.traffic_source, '(direct)')     AS source,
  COUNT(*)                                    AS order_count,
  ROUND(SUM(g.revenue), 0)                   AS total_revenue,
  ROUND(SUM(s.shipping_cost), 0)             AS total_shipping_cost,
  ROUND(AVG(s.shipping_cost), 0)             AS avg_shipping_cost_per_order,
  ROUND(SUM(s.shipping_cost) / SUM(g.revenue) * 100, 1) AS shipping_cost_ratio_pct
FROM
  ga4_purchases AS g
  LEFT JOIN `${PROJECT}.${DATASET}.shipping_costs` AS s
    ON g.transaction_id = s.order_id
GROUP BY
  medium,
  source
ORDER BY
  total_shipping_cost DESC
