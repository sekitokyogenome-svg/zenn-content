-- BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた
-- 出典: articles/bigquery-ec-rfm-analysis-email-strategy.md

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.rfm_segments` AS
-- 前述のRFM算出＋セグメント分類のクエリをここに記述
