-- 426. GA4×BigQueryを自社導入したEC事業者が最初の1週間で気づいたこと（Day 3：UNNESTとの格闘）
-- 用途: Day 3：UNNESTとの格闘
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_timestamp,
  event_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
FROM `${PROJECT}.${DATASET}.events_20260329`
WHERE event_name = 'page_view'
LIMIT 100
