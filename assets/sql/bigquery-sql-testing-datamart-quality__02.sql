-- 出典: BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み
-- 記事: articles/bigquery-sql-testing-datamart-quality.md（GA4エクスポートデータでのNULLチェックと一意性チェック）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- テスト: セッション集計テーブルの主キー重複チェック
SELECT
  event_date,
  session_id,
  COUNT(*) AS duplicate_count
FROM
  `${PROJECT}.${DATASET}.session_summary`
WHERE
  event_date = '2025-01-15'
GROUP BY
  event_date,
  session_id
HAVING
  COUNT(*) > 1
;
