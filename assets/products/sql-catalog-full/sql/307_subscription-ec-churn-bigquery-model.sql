-- 307. 定期購入ECの解約予兆をGA4行動ログから検知するBigQueryモデル（流入チャネル別に解約リスクを分析する）
-- 用途: 流入チャネル別に解約リスクを分析する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source,
  COUNT(DISTINCT user_pseudo_id) AS user_count,
  AVG(
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS avg_session_count,
  COUNTIF(
    EXISTS(
      SELECT 1
      FROM UNNEST(event_params) ep
      WHERE ep.key = 'page_location'
        AND ep.value.string_value LIKE '%/cancel%'
    )
  ) AS users_with_cancel_view
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  traffic_medium,
  traffic_source
ORDER BY
  users_with_cancel_view DESC
