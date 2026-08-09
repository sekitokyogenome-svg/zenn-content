-- 出典: GA4×BigQueryを自社導入したEC事業者が最初の1週間で気づいたこと
-- 記事: articles/ga4-bigquery-self-implement-ec-first-week.md（Day 4：セッションの概念が違う）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- セッション単位の集計
SELECT
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
  user_pseudo_id,
  MIN(event_timestamp) AS session_start,
  MAX(event_timestamp) AS session_end
FROM `${PROJECT}.${DATASET}.events_20260329`
GROUP BY session_id, user_pseudo_id
