-- Shopify × GA4のエコマース計測でデータが合わない問題を徹底解決する
-- 用途: transaction_idの重複を確認する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  ep.value.string_value AS transaction_id,
  COUNT(*) AS send_count
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) AS ep
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND event_name = 'purchase'
  AND ep.key = 'transaction_id'
GROUP BY
  transaction_id
HAVING
  send_count > 1
ORDER BY
  send_count DESC
