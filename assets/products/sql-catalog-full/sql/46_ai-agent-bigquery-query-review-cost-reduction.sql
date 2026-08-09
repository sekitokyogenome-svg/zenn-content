-- 46. AIエージェントにBigQueryのクエリレビューをさせてコスト削減した方法（BigQueryのコストが膨らむ典型的な原因）
-- 用途: BigQueryのコストが膨らむ典型的な原因
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  *
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
