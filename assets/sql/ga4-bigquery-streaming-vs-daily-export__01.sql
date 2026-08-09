-- 出典: GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け
-- 記事: articles/ga4-bigquery-streaming-vs-daily-export.md（日次テーブルを対象にしたクエリ例）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  event_name,
  (
    SELECT value.string_value
    FROM UNNEST(event_params)
    WHERE key = 'page_location'
  ) AS page_location,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
GROUP BY
  event_name,
  page_location
ORDER BY
  event_count DESC
LIMIT 50;
