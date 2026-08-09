-- GA4 × BigQuery × Looker Studioで完全自動のEC分析基盤を0から構築する全手順
-- 用途: mart_cohort（月次コホート分析）
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE TABLE `project.mart.mart_cohort` AS
WITH first_visit AS (
  SELECT
    user_pseudo_id,
    FORMAT_DATE('%Y-%m', MIN(session_date)) AS cohort_month
  FROM `project.staging.stg_sessions`
  GROUP BY user_pseudo_id
)
SELECT
  fv.cohort_month,
  FORMAT_DATE('%Y-%m', s.session_date) AS activity_month,
  DATE_DIFF(
    PARSE_DATE('%Y-%m', FORMAT_DATE('%Y-%m', s.session_date)),
    PARSE_DATE('%Y-%m', fv.cohort_month),
    MONTH
  ) AS months_since_first,
  COUNT(DISTINCT s.user_pseudo_id) AS returning_users
FROM `project.staging.stg_sessions` s
JOIN first_visit fv ON s.user_pseudo_id = fv.user_pseudo_id
GROUP BY cohort_month, activity_month, months_since_first
