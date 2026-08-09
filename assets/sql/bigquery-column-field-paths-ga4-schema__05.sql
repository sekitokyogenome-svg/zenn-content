-- 出典: BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する
-- 記事: articles/bigquery-column-field-paths-ga4-schema.md（実際の分析クエリへの応用）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_20250101`
WHERE
  event_name = 'session_start'
GROUP BY
  medium,
  source
ORDER BY
  sessions DESC;
