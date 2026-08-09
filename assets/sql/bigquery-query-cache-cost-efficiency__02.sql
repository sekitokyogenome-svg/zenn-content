-- 出典: BigQueryのクエリキャッシュの仕組みを理解してコスト効率を最大化する
-- 記事: articles/bigquery-query-cache-cost-efficiency.md（GA4データを活用するクエリでのキャッシュ設計）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- キャッシュを意識した集計例（対象期間を固定文字列で指定）
SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
  AND event_name = 'session_start'
GROUP BY
  event_date, medium, source
ORDER BY
  event_date
