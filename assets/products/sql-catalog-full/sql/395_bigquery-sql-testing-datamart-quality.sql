-- 395. BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み（テストの自動実行――BigQuery Scheduled Queriesを活用する）
-- 用途: テストの自動実行――BigQuery Scheduled Queriesを活用する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

INSERT INTO `${PROJECT}.${DATASET}.test_results` (
  test_name,
  test_date,
  result_count,
  status,
  executed_at
)
SELECT
  'null_session_id_check' AS test_name,
  CURRENT_DATE()          AS test_date,
  COUNT(*)                AS result_count,
  IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status,
  CURRENT_TIMESTAMP()     AS executed_at
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) AS ep
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
  AND ep.key = 'ga_session_id'
  AND ep.value.int_value IS NULL
;
