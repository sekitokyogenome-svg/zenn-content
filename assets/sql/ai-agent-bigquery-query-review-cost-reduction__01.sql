-- 出典: AIエージェントにBigQueryのクエリレビューをさせてコスト削減した方法
-- 記事: articles/ai-agent-bigquery-query-review-cost-reduction.md（BigQueryのコストが膨らむ典型的な原因）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- コストが高くなりがちな書き方（改善前）
SELECT
  *
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
