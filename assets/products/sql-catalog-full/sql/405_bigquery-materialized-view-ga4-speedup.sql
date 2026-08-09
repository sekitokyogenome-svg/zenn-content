-- 405. BigQueryのマテリアライズドビューでGA4集計クエリを高速化した（GA4のBigQueryエクスポートテーブル構造を理解する） その2
-- 用途: GA4のBigQueryエクスポートテーブル構造を理解する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX >= '20250601'
  AND event_name = 'session_start'
