-- 出典: BigQueryのクエリ結果をCloud Storageに自動エクスポートして外部ツール連携する
-- 記事: articles/bigquery-query-export-cloud-storage.md（GA4データをBigQueryで集計するSQLの書き方）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
GROUP BY
  medium,
  source
ORDER BY
  sessions DESC
;
