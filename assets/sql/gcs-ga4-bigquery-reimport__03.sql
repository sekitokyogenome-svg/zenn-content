-- 出典: GCSにバックアップしたGA4データをBigQueryに再インポートする手順
-- 記事: articles/gcs-ga4-bigquery-reimport.md（インポート後のデータ確認：GA4特有の構造を踏まえたSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  collected_traffic_source.manual_source AS source,
  collected_traffic_source.manual_medium AS medium,
  COUNT(*) AS session_count
FROM
  `${PROJECT}.${DATASET}.events_20240101`
WHERE
  event_name = 'session_start'
GROUP BY
  source,
  medium
ORDER BY
  session_count DESC;
