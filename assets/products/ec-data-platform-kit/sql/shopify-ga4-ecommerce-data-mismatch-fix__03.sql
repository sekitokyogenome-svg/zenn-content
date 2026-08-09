-- Shopify × GA4のエコマース計測でデータが合わない問題を徹底解決する
-- 用途: 流入元別のpurchase数を確認する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  cs.manual_medium AS medium,
  cs.manual_source AS source,
  COUNT(*) AS purchase_count,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `${PROJECT}.${DATASET}.events_*` AS e
LEFT JOIN
  UNNEST([e.collected_traffic_source]) AS cs
WHERE
  _TABLE_SUFFIX BETWEEN '20240601' AND '20240630'
  AND e.event_name = 'purchase'
GROUP BY
  medium,
  source
ORDER BY
  purchase_count DESC
