-- 出典: 中小ECのLTV分析をGA4×BigQueryで無料構築する方法【SQLテンプレ付き】
-- 記事: articles/ec-ltv-analysis-ga4-bigquery-free.md（SQL Template 3: シンプルLTV計算）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- シンプルLTV = 平均購入単価 × 平均購入回数 × 平均継続期間（年）
WITH user_metrics AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count,
    AVG(ecommerce.purchase_revenue) AS avg_purchase_value,
    DATE_DIFF(
      MAX(DATE(TIMESTAMP_MICROS(event_timestamp))),
      MIN(DATE(TIMESTAMP_MICROS(event_timestamp))),
      DAY
    ) / 365.0 AS lifespan_years
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    user_pseudo_id
  HAVING
    COUNT(*) >= 2  -- リピーターのみ対象
)
SELECT
  COUNT(*) AS user_count,
  ROUND(AVG(avg_purchase_value), 0) AS avg_purchase_value,
  ROUND(AVG(purchase_count), 1) AS avg_purchase_frequency,
  ROUND(AVG(lifespan_years), 2) AS avg_lifespan_years,
  ROUND(
    AVG(avg_purchase_value) * AVG(purchase_count) * AVG(lifespan_years), 0
  ) AS estimated_ltv
FROM
  user_metrics
