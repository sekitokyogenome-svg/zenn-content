-- 137. GA4×BigQueryのエクスポートが止まったときのトラブルシューティング（直近のテーブル作成状況をチェック）
-- 用途: 直近のテーブル作成状況をチェック
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  table_name,
  creation_time,
  TIMESTAMP_DIFF(CURRENT_TIMESTAMP(), creation_time, HOUR) AS hours_ago
FROM `${PROJECT}.${DATASET}.INFORMATION_SCHEMA.TABLES`
WHERE table_name LIKE 'events_%'
ORDER BY creation_time DESC
LIMIT 5
