-- 45. BigQueryのCOLUMN_FIELD_PATHSでGA4のネストされたスキーマを効率的に探索する
-- 用途: 実際の分析クエリへの応用
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
