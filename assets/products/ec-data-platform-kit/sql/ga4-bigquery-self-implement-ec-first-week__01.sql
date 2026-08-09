-- GA4×BigQueryを自社導入したEC事業者が最初の1週間で気づいたこと
-- 用途: Day 2：テーブル構造に驚く
-- 必要テーブル: events_20260329
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT event_name, COUNT(*) as event_count
FROM `${PROJECT}.${DATASET}.events_20260329`
GROUP BY event_name
ORDER BY event_count DESC
LIMIT 20
