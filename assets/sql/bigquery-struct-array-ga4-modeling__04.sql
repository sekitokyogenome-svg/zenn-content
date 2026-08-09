-- 出典: BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする
-- 記事: articles/bigquery-struct-array-ga4-modeling.md（流入元データをcollected_traffic_sourceから取得する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 流入元ごとのpage_viewイベント数を集計する例
SELECT
  event_date,
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  COUNT(*) AS page_view_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240801' AND '20240831'
  AND event_name = 'page_view'
GROUP BY
  event_date,
  source,
  medium
ORDER BY
  event_date,
  page_view_count DESC
