-- AIエージェントにBigQueryのクエリレビューをさせてコスト削減した方法
-- 用途: BigQueryのコストが膨らむ典型的な原因
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  *
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
