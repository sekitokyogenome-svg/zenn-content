-- Amazon広告とGA4自社ECデータをBigQueryで統合してチャネルミックスを最適化する
-- 用途: GA4のBigQueryエクスポートデータでチャネル別売上を集計する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(
    CASE
      WHEN event_name = 'purchase'
      THEN (
        SELECT value.double_value
        FROM UNNEST(event_params) AS ep
        WHERE ep.key = 'value'
      )
      ELSE 0
    END
  ) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
GROUP BY
  event_date,
  medium,
  source
ORDER BY
  event_date,
  revenue DESC
