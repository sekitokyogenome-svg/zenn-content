-- 出典: BigQuery MLの需要予測モデルでEC仕入れ量を最適化する実装手順
-- 記事: articles/bigquery-ml-demand-forecast-ec-inventory.md（データ準備：GA4のBigQueryエクスポートを活用する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'view_item') AS view_item_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
GROUP BY
  date, medium, source
ORDER BY
  date;
