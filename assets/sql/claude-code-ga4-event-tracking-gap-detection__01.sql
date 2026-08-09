-- 出典: Claude CodeでGA4のイベント計測漏れを自動検知・修正提案する仕組み
-- 記事: articles/claude-code-ga4-event-tracking-gap-detection.md（BigQueryでイベント計測漏れを検知するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- イベント別・日別の発火件数推移を集計
SELECT
  event_date,
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS session_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  event_date,
  event_name
ORDER BY
  event_name,
  event_date
