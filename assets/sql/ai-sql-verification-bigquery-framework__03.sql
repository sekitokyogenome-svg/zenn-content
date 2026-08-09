-- 出典: AIが生成したSQLは本当に正しいのか？BigQueryでの検証フレームワークを作った
-- 記事: articles/ai-sql-verification-bigquery-framework.md（AIがよく間違えるGA4 SQLのパターン）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- NG: 古い仕様のフィールドを参照（意図しないNULLが増える）
SELECT
  traffic_source.medium,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `${PROJECT}.${DATASET}.events_*`
GROUP BY 1

-- OK: collected_traffic_sourceを使用する
SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT user_pseudo_id) AS users
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
GROUP BY 1, 2
ORDER BY users DESC
