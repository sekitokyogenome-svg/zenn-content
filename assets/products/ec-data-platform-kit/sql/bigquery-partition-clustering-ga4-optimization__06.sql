-- BigQueryのパーティション・クラスタリングでGA4クエリを高速化する
-- 用途: パターン1：セッション集計テーブル
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE TABLE `your-project.mart.mart_sessions`
PARTITION BY event_date
CLUSTER BY session_medium, device_category
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  IFNULL(collected_traffic_source.manual_medium, '(none)') AS session_medium,
  device.category AS device_category
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
  AND event_name = 'session_start'
