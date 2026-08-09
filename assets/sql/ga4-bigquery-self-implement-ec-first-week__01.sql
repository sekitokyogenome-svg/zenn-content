-- 出典: GA4×BigQueryを自社導入したEC事業者が最初の1週間で気づいたこと
-- 記事: articles/ga4-bigquery-self-implement-ec-first-week.md（Day 2：テーブル構造に驚く）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- テーブルの中身を確認
SELECT event_name, COUNT(*) as event_count
FROM `${PROJECT}.${DATASET}.events_20260329`
GROUP BY event_name
ORDER BY event_count DESC
LIMIT 20
