-- 出典: GCSにバックアップしたGA4データをBigQueryに再インポートする手順
-- 記事: articles/gcs-ga4-bigquery-reimport.md（インポート後のデータ確認：GA4特有の構造を踏まえたSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  user_pseudo_id,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  event_name,
  event_timestamp
FROM
  `${PROJECT}.${DATASET}.events_20240101`
WHERE
  event_name = 'page_view'
LIMIT 100;
