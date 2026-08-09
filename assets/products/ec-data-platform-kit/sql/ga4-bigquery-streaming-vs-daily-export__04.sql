-- GA4 BigQueryエクスポートのストリーミング vs 日次の違いと使い分け
-- 用途: ストリーミングテーブルを使うべきシーン
-- 必要テーブル: events_intraday_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  FORMAT_TIMESTAMP('%H', TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS hour,
  COUNT(*) AS purchase_count,
  SUM(
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')
  ) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_intraday_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', CURRENT_DATE('Asia/Tokyo'))
  AND event_name = 'purchase'
GROUP BY
  hour
ORDER BY
  hour;
