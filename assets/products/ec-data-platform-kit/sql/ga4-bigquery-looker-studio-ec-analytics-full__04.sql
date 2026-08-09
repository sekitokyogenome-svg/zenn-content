-- GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順
-- 用途: mart_traffic（日別×チャネル別トラフィック）
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE TABLE `project.mart.mart_traffic` AS
SELECT
  session_date,
  source,
  medium,
  device_category,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING))) AS sessions,
  COUNT(DISTINCT IF(has_purchase = 1, CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)), NULL)) AS converting_sessions,
  SUM(session_revenue) AS total_revenue
FROM `project.staging.stg_sessions`
GROUP BY session_date, source, medium, device_category
