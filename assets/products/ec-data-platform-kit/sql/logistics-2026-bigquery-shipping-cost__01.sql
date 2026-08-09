-- 2024年問題に備えるデータ基盤―配送コストをBigQueryで最適化する
-- 用途: 流入経路別・配送コスト分析のSQLサンプル
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
