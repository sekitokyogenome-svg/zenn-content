-- BigQueryでSQLテストを書く方法―データマートの品質を担保する仕組み
-- 用途: GA4エクスポートデータでのNULLチェックと一意性チェック
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
