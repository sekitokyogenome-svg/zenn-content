-- ECの同梱チラシ施策効果をGA4のオフラインCV連携×BigQueryで測定する
-- 用途: BigQueryでチラシ経由CV数・売上を集計するSQLの書き方
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_params AS (
  SELECT
    user_pseudo_id,
    -- ga_session_idはevent_paramsをUNNESTして取得
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    collected_traffic_source.manual_campaign_name AS campaign,
    event_name,
    event_timestamp,
    -- purchase金額
    (
      SELECT value.double_value
      FROM UNNEST(event_params)
      WHERE key = 'value'
    ) AS purchase_value
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250731'
    AND event_name IN ('session_start', 'purchase')
),
flyer_sessions AS (
  -- チラシ（print）経由のセッションを特定
  SELECT DISTINCT
    user_pseudo_id,
    ga_session_id
  FROM session_params
  WHERE
    medium = 'print'
    AND source = 'flyer'
    AND event_name = 'session_start'
)
SELECT
  s.campaign,
  COUNT(DISTINCT CONCAT(sp.user_pseudo_id, CAST(sp.ga_session_id AS STRING))) AS sessions,
  COUNT(DISTINCT CASE WHEN sp.event_name = 'purchase' THEN sp.user_pseudo_id END) AS purchasers,
  SUM(CASE WHEN sp.event_name = 'purchase' THEN sp.purchase_value ELSE 0 END) AS total_revenue
FROM
  session_params sp
INNER JOIN
  flyer_sessions s
  ON sp.user_pseudo_id = s.user_pseudo_id
  AND sp.ga_session_id = s.ga_session_id
GROUP BY
  s.campaign
ORDER BY
  total_revenue DESC;
