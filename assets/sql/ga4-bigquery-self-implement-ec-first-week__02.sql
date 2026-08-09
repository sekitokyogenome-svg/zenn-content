-- 出典: GA4×BigQueryを自社導入したEC事業者が最初の1週間で気づいたこと
-- 記事: articles/ga4-bigquery-self-implement-ec-first-week.md（Day 3：UNNESTとの格闘）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- event_paramsからpage_locationを取得
SELECT
  event_timestamp,
  event_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
FROM `${PROJECT}.${DATASET}.events_20260329`
WHERE event_name = 'page_view'
LIMIT 100
