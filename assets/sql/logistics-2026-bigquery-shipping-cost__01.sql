-- 出典: 2024年問題に備えるデータ基盤―配送コストをBigQueryで最適化する
-- 記事: articles/logistics-2026-bigquery-shipping-cost.md（流入経路別・配送コスト分析のSQLサンプル）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- GA4の購買イベントから流入元と注文IDを取得する
SELECT
  event_date,
  -- ga_session_idはevent_paramsをUNNESTして取得する
  (
    SELECT ep.value.int_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'ga_session_id'
  ) AS session_id,
  -- 流入元はcollected_traffic_sourceから取得する
  collected_traffic_source.manual_medium  AS traffic_medium,
  collected_traffic_source.manual_source  AS traffic_source,
  -- ecommerce情報
  ecommerce.purchase_revenue             AS revenue,
  (
    SELECT ep.value.string_value
    FROM UNNEST(event_params) AS ep
    WHERE ep.key = 'transaction_id'
  ) AS transaction_id
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260731'
  AND event_name = 'purchase'
