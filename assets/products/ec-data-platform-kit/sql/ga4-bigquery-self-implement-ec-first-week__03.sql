-- GA4×BigQueryを自社導入したEC事業者が最初の1週間で気づいたこと
-- 用途: Day 4：セッションの概念が違う
-- 必要テーブル: events_20260329
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
  user_pseudo_id,
  MIN(event_timestamp) AS session_start,
  MAX(event_timestamp) AS session_end
FROM `${PROJECT}.${DATASET}.events_20260329`
GROUP BY session_id, user_pseudo_id
