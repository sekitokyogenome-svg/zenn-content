-- BigQueryでGA4のeコマースイベントを完全解析する【purchase/add_to_cart】
-- 用途: カテゴリ別・商品別の売上集計
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT ecommerce.transaction_id) AS transactions,
  ROUND(SUM(ecommerce.purchase_revenue), 0) AS total_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260101' AND '20260331'
  AND event_name = 'purchase'
GROUP BY
  medium, source
ORDER BY
  total_revenue DESC
