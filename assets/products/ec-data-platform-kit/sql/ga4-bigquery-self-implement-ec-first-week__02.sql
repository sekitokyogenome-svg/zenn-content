-- GA4×BigQueryを自社導入したEC事業者が最初の1週間で気づいたこと
-- 用途: Day 3：UNNESTとの格闘
-- 必要テーブル: events_20260329
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_timestamp,
  event_name,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location
FROM `${PROJECT}.${DATASET}.events_20260329`
WHERE event_name = 'page_view'
LIMIT 100
