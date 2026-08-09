-- 321. BigQueryでEC受注データ×GA4データを結合して正確な売上帰属分析をする（データ構造を理解する：GA4のBigQueryエクスポートとは）
-- 用途: データ構造を理解する：GA4のBigQueryエクスポートとは
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  user_pseudo_id,
  -- ga_session_idはevent_paramsをUNNESTして取得する
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  -- 流入元はcollected_traffic_sourceから取得
  collected_traffic_source.manual_source     AS traffic_source,
  collected_traffic_source.manual_medium     AS traffic_medium,
  collected_traffic_source.manual_campaign_name AS campaign_name,
  event_timestamp,
  event_name
FROM
  `${PROJECT}.${DATASET}.events_20260101`
WHERE
  event_name = 'session_start'
