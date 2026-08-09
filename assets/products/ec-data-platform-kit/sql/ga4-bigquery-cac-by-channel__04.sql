-- GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する
-- 用途: CACの評価基準
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH customer_ltv AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count,
    SUM(ecommerce.purchase_revenue) AS total_revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)

SELECT
  ROUND(AVG(total_revenue), 0) AS avg_ltv,
  ROUND(PERCENTILE_CONT(total_revenue, 0.5) OVER(), 0) AS median_ltv,
  ROUND(AVG(purchase_count), 1) AS avg_purchase_count
FROM customer_ltv
LIMIT 1
