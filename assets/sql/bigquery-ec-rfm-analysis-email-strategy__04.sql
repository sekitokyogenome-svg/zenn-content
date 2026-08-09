-- 出典: BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた
-- 記事: articles/bigquery-ec-rfm-analysis-email-strategy.md（BigQueryでの定期更新）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- スケジュールクエリとして登録する
CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.rfm_segments` AS
-- 前述のRFM算出＋セグメント分類のクエリをここに記述
