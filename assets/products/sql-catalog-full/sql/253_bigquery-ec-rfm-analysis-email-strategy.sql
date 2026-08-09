-- 253. BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた（セグメント別の集計）
-- 用途: セグメント別の集計
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  segment,
  COUNT(*) AS user_count,
  ROUND(AVG(recency), 0) AS avg_recency_days,
  ROUND(AVG(frequency), 1) AS avg_frequency,
  ROUND(AVG(monetary), 0) AS avg_monetary
FROM rfm_segmented
GROUP BY segment
ORDER BY avg_monetary DESC;
