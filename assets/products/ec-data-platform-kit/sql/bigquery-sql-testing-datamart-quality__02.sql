-- BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み
-- 用途: GA4エクスポートデータでのNULLチェックと一意性チェック
-- 必要テーブル: session_summary
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
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
