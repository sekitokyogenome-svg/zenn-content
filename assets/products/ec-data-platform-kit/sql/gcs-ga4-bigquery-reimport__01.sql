-- GCSにバックアップしたGA4データをBigQueryに再インポートする手順
-- 用途: インポート後のデータ確認：GA4特有の構造を踏まえたSQL
-- 必要テーブル: events_20240101
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_name,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_20240101`
GROUP BY
  event_name
ORDER BY
  event_count DESC
LIMIT 20;
