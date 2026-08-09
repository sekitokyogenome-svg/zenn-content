-- BigQueryでGA4データのコスト管理・クエリ最適化入門
-- 用途: テクニック3：中間テーブルやビューを活用する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE TABLE `your-project.staging.sessions_202603` AS
SELECT
  event_date,
  CONCAT(
    user_pseudo_id, '.',
    CAST(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  user_pseudo_id,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
