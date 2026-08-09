-- EC広告費の予算配分をBigQueryの過去データから最適化するフレームワーク
-- 用途: 売上貢献額ベースで予算配分の優先順位をつける
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH purchase_events AS (
  SELECT
    CONCAT(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ga_session_id'),
      '-',
      user_pseudo_id
    ) AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value') AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
                      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name = 'purchase'
)
SELECT
  COALESCE(medium, '(none)') AS medium,
  COALESCE(source, '(direct)') AS source,
  COUNT(*) AS purchase_count,
  ROUND(SUM(revenue), 0) AS total_revenue,
  ROUND(AVG(revenue), 0) AS avg_order_value
FROM purchase_events
GROUP BY medium, source
ORDER BY total_revenue DESC;
