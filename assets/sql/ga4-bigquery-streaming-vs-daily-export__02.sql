-- 出典: GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け
-- 記事: articles/ga4-bigquery-streaming-vs-daily-export.md（ga_session_id の取得方法）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  event_name,
  event_timestamp
FROM
  `${PROJECT}.${DATASET}.events_20250801`
WHERE
  event_name = 'purchase'
LIMIT 100;
