-- 出典: BigQueryのクエリコストを月1万円以下に抑える7つの実践テクニック
-- 記事: articles/bigquery-query-cost-under-10k-techniques.md（テクニック2：SELECT * を避けて必要な列だけ取得する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- ga_session_id と流入元を取得する例
SELECT
  user_pseudo_id,
  event_timestamp,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND event_name = 'session_start'
