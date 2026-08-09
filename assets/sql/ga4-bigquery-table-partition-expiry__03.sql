-- 出典: GA4×BigQueryのテーブル肥大化を防ぐパーティション有効期限の設定方法
-- 記事: articles/ga4-bigquery-table-partition-expiry.md（方法2：パーティションテーブルに統合して有効期限を管理する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- GA4のイベントデータをパーティションテーブルとして統合する
CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.events_partitioned`
PARTITION BY event_date
OPTIONS (
  partition_expiration_days = 365
)
AS
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_date,
  event_timestamp,
  event_name,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  ecommerce.purchase_revenue AS purchase_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND FORMAT_DATE('%Y%m%d', CURRENT_DATE());
