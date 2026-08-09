-- 38. BigQueryのSTRUCT・ARRAY型を活用してGA4データを効率的にモデリングする（流入元データをcollected_traffic_sourceから取得する）
-- 用途: 流入元データをcollected_traffic_sourceから取得する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
