-- 出典: NotebookLM × BigQueryエクスポートでGA4データを対話的に分析する
-- 記事: articles/notebooklm-bigquery-ga4-interactive-analysis.md（GA4データをBigQueryからCSVに取り出す）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  cs.manual_medium AS medium,
  cs.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `${PROJECT}.${DATASET}.events_*`
  , UNNEST(collected_traffic_source) AS cs
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
GROUP BY
  medium, source
ORDER BY
  sessions DESC
LIMIT 100;
