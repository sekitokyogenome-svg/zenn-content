-- 16. BigQueryのGeminiアシスタントで非エンジニアが自力でSQL分析できるか検証した（流入元別のセッション分析に挑戦）
-- 用途: 流入元別のセッション分析に挑戦
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value
     FROM UNNEST(event_params) AS ep
     WHERE ep.key = 'ga_session_id')
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  sessions DESC;
