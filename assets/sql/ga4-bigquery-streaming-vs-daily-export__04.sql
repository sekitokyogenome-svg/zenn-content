-- 出典: GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け
-- 記事: articles/ga4-bigquery-streaming-vs-daily-export.md（ストリーミングテーブルを使うべきシーン）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  FORMAT_TIMESTAMP('%H', TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS hour,
  COUNT(*) AS purchase_count,
  SUM(
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_intraday_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', CURRENT_DATE('Asia/Tokyo'))
  AND event_name = 'purchase'
GROUP BY
  hour
ORDER BY
  hour;
