-- 出典: GA4のデータをBigQueryに繋ぐと何が変わるのか【3層設計まで解説】
-- 記事: articles/ga4-bigquery-3layer-design.md（生データをそのまま使わない方がいい理由）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 生データへのクエリ例（冗長になりがち）
SELECT
  user_pseudo_id,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
  AND event_name = 'page_view'
