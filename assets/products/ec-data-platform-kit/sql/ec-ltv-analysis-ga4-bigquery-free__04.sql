-- 中小ECのLTV分析をGA4×BigQueryで無料構築する方法【SQLテンプレ付き】
-- 用途: SQL Template 4: コホート別LTV（月次リテンション）
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH user_cohort AS (
  SELECT
    user_pseudo_id,
    MIN(FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(event_timestamp))) AS cohort_month
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    user_pseudo_id
),
purchase_data AS (
  SELECT
    e.user_pseudo_id,
    FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(e.event_timestamp)) AS purchase_month,
    SUM(e.ecommerce.purchase_revenue) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*` e
  WHERE
    e.event_name = 'purchase'
  GROUP BY
    e.user_pseudo_id, purchase_month
)
SELECT
  uc.cohort_month,
  DATE_DIFF(
    PARSE_DATE('%Y-%m', pd.purchase_month),
    PARSE_DATE('%Y-%m', uc.cohort_month),
    MONTH
  ) AS months_since_first_purchase,
  COUNT(DISTINCT uc.user_pseudo_id) AS active_users,
  (SELECT COUNT(DISTINCT user_pseudo_id) FROM user_cohort WHERE cohort_month = uc.cohort_month) AS cohort_size,
  ROUND(SUM(pd.revenue), 0) AS monthly_revenue,
  ROUND(SUM(pd.revenue) / (SELECT COUNT(DISTINCT user_pseudo_id) FROM user_cohort WHERE cohort_month = uc.cohort_month), 0) AS revenue_per_cohort_user
FROM
  user_cohort uc
INNER JOIN
  purchase_data pd ON uc.user_pseudo_id = pd.user_pseudo_id
GROUP BY
  uc.cohort_month, months_since_first_purchase, cohort_size
ORDER BY
  uc.cohort_month, months_since_first_purchase
