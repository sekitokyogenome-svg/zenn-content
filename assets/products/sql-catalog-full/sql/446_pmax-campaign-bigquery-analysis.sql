-- 446. P-MAXキャンペーンの配信実績をBigQueryで詳細分析する方法（SQLでP-MAX流入のランディングページを分析する）
-- 用途: SQLでP-MAX流入のランディングページを分析する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_date,
  collected_traffic_source.manual_source   AS source,
  collected_traffic_source.manual_medium   AS medium,
  (SELECT ep.value.string_value
   FROM UNNEST(event_params) AS ep
   WHERE ep.key = 'page_location')         AS landing_page,
  COUNT(DISTINCT
    (SELECT ep.value.string_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  )                                         AS sessions,
  COUNTIF(event_name = 'purchase')          AS conversions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
  AND collected_traffic_source.manual_source = 'google'
  AND collected_traffic_source.manual_medium = 'cpc'
GROUP BY
  event_date, source, medium, landing_page
ORDER BY
  sessions DESC
LIMIT 50
