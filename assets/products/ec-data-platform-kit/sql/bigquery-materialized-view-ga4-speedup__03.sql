-- BigQueryのマテリアライズドビューでGA4集計クエリを高速化した
-- 用途: マテリアライズドビューの作成手順
-- 必要テーブル: events_*, mv_ga4_session_summary
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE MATERIALIZED VIEW `${PROJECT}.${DATASET}.mv_ga4_session_summary`
OPTIONS (
  enable_refresh = true,
  refresh_interval_minutes = 60
)
AS
SELECT
  event_date,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  COUNTIF(event_name = 'purchase') AS purchase_count,
  SUM(
    CASE
      WHEN event_name = 'purchase'
      THEN (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'value')
      ELSE 0
    END
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
GROUP BY
  event_date,
  source,
  medium,
  user_pseudo_id,
  ga_session_id
