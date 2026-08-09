-- 出典: AIエージェントにBigQueryのクエリレビューをさせてコスト削減した方法
-- 記事: articles/ai-agent-bigquery-query-review-cost-reduction.md（AIが提案した最適化クエリの例）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- AIが提案した改善後のクエリ
SELECT
  event_date,
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  ecommerce.purchase_revenue AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250731'
  AND event_name = 'purchase'
