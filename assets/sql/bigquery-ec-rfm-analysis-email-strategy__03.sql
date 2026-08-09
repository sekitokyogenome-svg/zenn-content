-- 出典: BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた
-- 記事: articles/bigquery-ec-rfm-analysis-email-strategy.md（セグメント別の集計）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  segment,
  COUNT(*) AS user_count,
  ROUND(AVG(recency), 0) AS avg_recency_days,
  ROUND(AVG(frequency), 1) AS avg_frequency,
  ROUND(AVG(monetary), 0) AS avg_monetary
FROM rfm_segmented
GROUP BY segment
ORDER BY avg_monetary DESC;
