-- Looker StudioでBigQueryに接続するときの料金を最小化する設定
-- 用途: 方法4: パーティションテーブルを活用する
-- 必要テーブル: events_*, sessions_partitioned
-- コスト: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE TABLE `${PROJECT}.${DATASET}.sessions_partitioned`
PARTITION BY event_date
CLUSTER BY traffic_source
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  user_pseudo_id,
  traffic_source.source AS traffic_source,
  traffic_source.medium AS traffic_medium,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id
FROM
  `${PROJECT}.${DATASET}.events_*`;
