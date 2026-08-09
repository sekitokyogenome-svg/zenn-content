-- 出典: BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み
-- 記事: articles/bigquery-sql-testing-datamart-quality.md（流入元データの整合性チェック）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- テスト: 想定外の流入mediumが混入していないかを確認する
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
