-- 418. GCSにバックアップしたGA4データをBigQueryに再インポートする手順（インポート後のデータ確認：GA4特有の構造を踏まえたSQL） その3
-- 用途: インポート後のデータ確認：GA4特有の構造を踏まえたSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
