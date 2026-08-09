-- Cookie規制後のEC広告効果測定をファーストパーティデータ×BigQueryで再構築する
-- 用途: BigQueryでチャネル別コンバージョンを集計するSQL
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH purchase_sessions AS (
  SELECT
    -- セッションIDはevent_paramsをUNNESTして取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    user_pseudo_id,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_source       AS traffic_source,
    collected_traffic_source.manual_medium       AS traffic_medium,
    collected_traffic_source.manual_campaign_name AS campaign_name,
    (
      SELECT ep.value.double_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'value'
    ) AS purchase_value,
    event_date
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND event_name = 'purchase'
)

SELECT
  traffic_medium,
  traffic_source,
  campaign_name,
  COUNT(*)                         AS purchase_count,
  COUNT(DISTINCT user_pseudo_id)   AS unique_buyers,
  ROUND(SUM(purchase_value), 0)    AS total_revenue
FROM
  purchase_sessions
GROUP BY
  traffic_medium,
  traffic_source,
  campaign_name
ORDER BY
  total_revenue DESC
;
