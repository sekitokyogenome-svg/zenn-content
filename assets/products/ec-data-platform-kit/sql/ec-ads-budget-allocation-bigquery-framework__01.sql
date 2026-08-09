-- EC広告費の予算配分をBigQueryの過去データから最適化するフレームワーク
-- 用途: チャネル別のパフォーマンスをBigQueryで可視化する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_base AS (
  SELECT
    CONCAT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ga_session_id'),
      '-',
      user_pseudo_id
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_name
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
                      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),
session_summary AS (
  SELECT
    session_id,
    MAX(medium) AS medium,
    MAX(source) AS source,
    COUNTIF(event_name = 'session_start') AS sessions,
    COUNTIF(event_name = 'purchase') AS purchases
  FROM session_base
  GROUP BY session_id
)
SELECT
  COALESCE(medium, '(none)') AS medium,
  COALESCE(source, '(direct)') AS source,
  COUNT(DISTINCT session_id) AS total_sessions,
  SUM(purchases) AS total_purchases,
  ROUND(SAFE_DIVIDE(SUM(purchases), COUNT(DISTINCT session_id)) * 100, 2) AS cvr_pct
FROM session_summary
GROUP BY medium, source
ORDER BY total_purchases DESC
LIMIT 20;
