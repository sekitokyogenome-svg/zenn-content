-- BigQueryでEC顧客をRFM分析してセグメント別メルマガ戦略を立てた
-- 用途: BigQueryでの定期更新
-- 必要テーブル: rfm_segments
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.rfm_segments` AS
-- 前述のRFM算出＋セグメント分類のクエリをここに記述
