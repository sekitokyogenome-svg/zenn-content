-- 出典: BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み
-- 記事: articles/bigquery-sql-testing-datamart-quality.md（流入元データの整合性チェック）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- テスト: 許可されていないmediumが存在すれば結果を返す
WITH allowed_mediums AS (
  SELECT medium FROM UNNEST(['organic', 'cpc', 'email', 'social', 'referral', '(none)']) AS medium
),
actual_mediums AS (
  SELECT DISTINCT
    collected_traffic_source.manual_medium AS medium
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_medium IS NOT NULL
)
SELECT
  a.medium AS unexpected_medium
FROM
  actual_mediums a
LEFT JOIN
  allowed_mediums al ON a.medium = al.medium
WHERE
  al.medium IS NULL
;
