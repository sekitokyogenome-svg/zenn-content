-- 367. BigQueryのクエリキャッシュの仕組みを理解してコスト効率を最大化する（GA4データを活用するクエリでのキャッシュ設計）
-- 用途: GA4データを活用するクエリでのキャッシュ設計
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
