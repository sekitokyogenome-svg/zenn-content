-- EC事業の粗利率をBigQueryで商品×チャネル別に自動計算する仕組み
-- 用途: BigQueryで流入チャネルと購入を紐づけるSQL
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_source AS (
  SELECT
    -- ga_session_idはevent_params経由で取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    user_pseudo_id,
    -- 流入元はcollected_traffic_sourceを使用
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_date
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'session_start'
),

purchase_events AS (
  SELECT
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    user_pseudo_id,
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'transaction_id'
    ) AS transaction_id,
    (
      SELECT ep.value.double_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS revenue,
    event_date
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
)

SELECT
  ss.medium,
  ss.source,
  pe.transaction_id,
  pe.revenue,
  pe.event_date
FROM
  purchase_events AS pe
LEFT JOIN
  session_source AS ss
  ON pe.ga_session_id = ss.ga_session_id
  AND pe.user_pseudo_id = ss.user_pseudo_id
WHERE
  pe.transaction_id IS NOT NULL
