-- 出典: GCSにバックアップしたGA4データをBigQueryに再インポートする手順
-- 記事: articles/gcs-ga4-bigquery-reimport.md（インポート後のデータ確認：GA4特有の構造を踏まえたSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
