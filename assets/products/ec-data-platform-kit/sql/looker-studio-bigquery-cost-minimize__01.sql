-- Looker StudioでBigQueryに接続するときの料金を最小化する設定
-- 用途: 方法2: マテリアライズドビューで集計済みデータを用意する
-- 必要テーブル: events_*, mv_daily_sessions
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE MATERIALIZED VIEW `${PROJECT}.${DATASET}.mv_daily_sessions`
OPTIONS (
  enable_refresh = true,
  refresh_interval_minutes = 720
)
AS
SELECT
  event_date,
  COUNT(DISTINCT CONCAT(user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING))
  ) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
GROUP BY
  event_date;
