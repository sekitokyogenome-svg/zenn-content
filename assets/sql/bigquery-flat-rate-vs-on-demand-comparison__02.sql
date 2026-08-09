-- 出典: BigQueryのフラットレート vs オンデマンド料金を実データで比較してどちらが安いか検証した
-- 記事: articles/bigquery-flat-rate-vs-on-demand-comparison.md（実際のクエリで処理量を比較してみた）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = "ga_session_id"
    LIMIT 1
  ) AS ga_session_id
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN "20240101" AND "20240131"
  AND event_name = "session_start"
