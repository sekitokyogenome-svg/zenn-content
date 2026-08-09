-- 出典: Gemini in BigQuery Studioのリソース検出機能でマルチプロジェクト分析を効率化する
-- 記事: articles/gemini-bigquery-studio-resource-discovery.md（流入元分析への応用）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(
    (SELECT ep.value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'value')
  ) AS total_revenue
FROM
  `project-brand-a.analytics_XXXXXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase'
GROUP BY
  medium, source
ORDER BY
  purchases DESC
LIMIT 20;
