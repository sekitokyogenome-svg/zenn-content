-- 2024年問題に備えるデータ基盤―配送コストをBigQueryで最適化する
-- 用途: 流入経路別・配送コスト分析のSQLサンプル
-- 必要テーブル: events_*, shipping_costs
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
