-- 27. dbt × BigQueryで再現可能なデータパイプラインを構築する入門【GA4データ編】
-- 用途: GA4イベントデータからセッション・流入元を抽出するモデルを作る
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH raw_events AS (
  SELECT
    user_pseudo_id,
    event_date,
    event_timestamp,
    event_name,
    -- ga_session_idはevent_paramsをUNNESTして取得する
    (
      SELECT value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    -- 流入元はcollected_traffic_sourceから取得する
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source
  FROM
    `your-gcp-project-id.analytics_XXXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'session_start'
),

sessions AS (
  SELECT
    user_pseudo_id,
    ga_session_id,
    MIN(event_date) AS session_date,
    MIN(event_timestamp) AS session_start_ts,
    MAX(medium) AS medium,
    MAX(source) AS source
  FROM raw_events
  WHERE ga_session_id IS NOT NULL
  GROUP BY
    user_pseudo_id,
    ga_session_id
)

SELECT * FROM sessions
