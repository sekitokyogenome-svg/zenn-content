-- GA4×BigQueryのエクスポートが止まったときのトラブルシューティング
-- 用途: STEP 1：最新テーブルの日付を確認する
-- 必要テーブル: __TABLES__
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  table_id,
  TIMESTAMP_MILLIS(last_modified_time) AS last_modified
FROM `${PROJECT}.${DATASET}.__TABLES__`
WHERE table_id LIKE 'events_%'
ORDER BY table_id DESC
LIMIT 10
