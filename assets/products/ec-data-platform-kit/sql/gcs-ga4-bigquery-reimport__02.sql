-- GCSにバックアップしたGA4データをBigQueryに再インポートする手順
-- 用途: インポート後のデータ確認：GA4特有の構造を踏まえたSQL
-- 必要テーブル: events_20240101
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
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
