-- 出典: GA4のBigQueryエクスポート完全設定ガイド【2026年版】
-- 記事: articles/ga4-bigquery-export-setup-guide-2026.md（セッションIDを取得するクエリ例）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
  event_name,
  event_timestamp
FROM
  `${PROJECT}.${DATASET}.events_20260328`
WHERE
  event_name = 'page_view'
LIMIT 100
