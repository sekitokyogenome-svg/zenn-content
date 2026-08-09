-- 出典: BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み
-- 記事: articles/bigquery-sql-testing-datamart-quality.md（GA4エクスポートデータでのNULLチェックと一意性チェック）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- テスト: ga_session_id のNULL件数を確認する
SELECT
  COUNT(*) AS null_session_id_count
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) AS ep
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
  AND ep.key = 'ga_session_id'
  AND ep.value.int_value IS NULL
;
