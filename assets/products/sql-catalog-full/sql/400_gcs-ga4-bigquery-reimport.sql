-- 400. GCSにバックアップしたGA4データをBigQueryに再インポートする手順（インポート後のデータ確認：GA4特有の構造を踏まえたSQL） その2
-- 用途: インポート後のデータ確認：GA4特有の構造を踏まえたSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
