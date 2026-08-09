-- GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け
-- 用途: ga_session_id の取得方法
-- 必要テーブル: events_20250801
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
  `${PROJECT}.${DATASET}.events_20250801`
WHERE
  event_name = 'purchase'
LIMIT 100;
