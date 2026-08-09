-- 391. BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み（流入元データの整合性チェック） その2
-- 用途: 流入元データの整合性チェック
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  collected_traffic_source.manual_medium AS medium,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
  AND event_name = 'session_start'
GROUP BY
  medium
ORDER BY
  event_count DESC
;
