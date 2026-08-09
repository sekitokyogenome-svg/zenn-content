-- 出典: Claude CodeでGA4のイベント計測漏れを自動検知・修正提案する仕組み
-- 記事: articles/claude-code-ga4-event-tracking-gap-detection.md（BigQueryでイベント計測漏れを検知するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 流入元別にイベント発火件数を集計
SELECT
  event_date,
  event_name,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name IN ('add_to_cart', 'begin_checkout', 'purchase')
GROUP BY
  event_date,
  event_name,
  medium,
  source
ORDER BY
  event_date,
  event_name
