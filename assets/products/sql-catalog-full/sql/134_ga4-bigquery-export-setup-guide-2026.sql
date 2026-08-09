-- 134. GA4のBigQueryエクスポート完全設定ガイド【2026年版】（セッションIDを取得するクエリ例）
-- 用途: セッションIDを取得するクエリ例
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
