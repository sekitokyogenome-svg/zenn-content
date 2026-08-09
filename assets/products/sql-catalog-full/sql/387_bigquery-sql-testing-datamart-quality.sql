-- 387. BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み（GA4エクスポートデータでのNULLチェックと一意性チェック） その1
-- 用途: GA4エクスポートデータでのNULLチェックと一意性チェック
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
