-- 出典: Amazon広告とGA4自社ECデータをBigQueryで統合してチャネルミックスを最適化する
-- 記事: articles/amazon-ads-ga4-bigquery-channel-mix.md（GA4のBigQueryエクスポートデータでチャネル別売上を集計する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
