-- 31. BigQueryのラベル機能でプロジェクト横断のコスト配分を自動管理する（クエリジョブへのラベル付与方法）
-- 用途: クエリジョブへのラベル付与方法
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
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
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND event_name = 'session_start'
GROUP BY
  medium, source
ORDER BY
  sessions DESC
