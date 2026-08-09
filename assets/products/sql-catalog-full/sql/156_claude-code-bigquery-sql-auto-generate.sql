-- 156. Claude CodeでBigQueryのSQLを自然言語から自動生成する（実例2：purchaseイベントから商品別売上を集計）
-- 用途: 実例2：purchaseイベントから商品別売上を集計
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  items.item_name,
  SUM(items.item_revenue) AS total_revenue,
  COUNT(*) AS purchase_count
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(items) AS items
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
GROUP BY
  items.item_name
ORDER BY
  total_revenue DESC
