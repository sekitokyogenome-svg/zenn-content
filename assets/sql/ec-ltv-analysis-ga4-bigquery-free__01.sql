-- 出典: 中小ECのLTV分析をGA4×BigQueryで無料構築する方法【SQLテンプレ付き】
-- 記事: articles/ec-ltv-analysis-ga4-bigquery-free.md（SQL Template 1: ユーザーごとの平均購入単価）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- ユーザーごとの平均購入単価
SELECT
  user_pseudo_id,
  COUNT(*) AS purchase_count,
  SUM(ecommerce.purchase_revenue) AS total_revenue,
  AVG(ecommerce.purchase_revenue) AS avg_purchase_value
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'purchase'
  AND _TABLE_SUFFIX BETWEEN '20250101' AND '20260329'
GROUP BY
  user_pseudo_id
ORDER BY
  total_revenue DESC
