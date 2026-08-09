-- 409. 小規模EC事業者がBigQueryを無料枠内で運用し続けるための設計戦略（クエリ設計でスキャン量を最小化する）
-- 用途: クエリ設計でスキャン量を最小化する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT *
FROM `${PROJECT}.${DATASET}.events_*`
WHERE event_name = 'purchase';

-- 良い例：期間を絞り込む
SELECT *
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  AND event_name = 'purchase';
