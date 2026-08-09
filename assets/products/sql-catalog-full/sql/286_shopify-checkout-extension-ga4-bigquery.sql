-- 286. Shopifyのチェックアウト拡張機能のイベントをGA4×BigQueryで分析する（BigQueryでチェックアウトイベントを集計するSQL）
-- 用途: BigQueryでチェックアウトイベントを集計するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH base AS (
  SELECT
    event_date,
    event_name,
    -- ga_session_idはevent_paramsをUNNESTして取得する
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    -- チェックアウトステップ（カスタムパラメータ）を取得
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'checkout_step'
    ) AS checkout_step,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
    AND event_name = 'checkout_step_reached'
)

SELECT
  event_date,
  checkout_step,
  medium,
  source,
  COUNT(DISTINCT ga_session_id) AS sessions,
  COUNT(*) AS event_count
FROM base
GROUP BY
  event_date,
  checkout_step,
  medium,
  source
ORDER BY
  event_date,
  checkout_step;
