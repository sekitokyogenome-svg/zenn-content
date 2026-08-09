-- BigQueryのクエリコストを月1万円以下に抑える7つの実践テクニック
-- 用途: テクニック4：マテリアライズドビューで集計コストを自動化する
-- 必要テーブル: events_*, mv_session_traffic
-- コスト: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE MATERIALIZED VIEW `${PROJECT}.${DATASET}.mv_session_traffic`
AS
SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  COUNT(DISTINCT user_pseudo_id) AS unique_users
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'session_start'
GROUP BY
  event_date,
  traffic_medium,
  traffic_source
