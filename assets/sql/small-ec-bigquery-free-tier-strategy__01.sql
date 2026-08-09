-- 出典: 小規模EC事業者がBigQueryを無料枠内で運用し続けるための設計戦略
-- 記事: articles/small-ec-bigquery-free-tier-strategy.md（クエリ設計でスキャン量を最小化する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 悪い例：全期間スキャンが走る
SELECT *
FROM `${PROJECT}.${DATASET}.events_*`
WHERE event_name = 'purchase';

-- 良い例：期間を絞り込む
SELECT *
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase';
