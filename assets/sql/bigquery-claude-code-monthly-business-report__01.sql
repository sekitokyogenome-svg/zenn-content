-- 出典: BigQuery × Claude Codeで月次事業報告書を自動作成する仕組み
-- 記事: articles/bigquery-claude-code-monthly-business-report.md（セッション・CV・売上の月次サマリ）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 月次KPIサマリ
WITH monthly_data AS (
  SELECT
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params)
            WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase'
      THEN user_pseudo_id END) AS purchasers,
    SUM(CASE WHEN event_name = 'purchase'
      THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(
      DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(
      DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
  GROUP BY month
)
SELECT
  month,
  sessions,
  purchasers,
  revenue,
  SAFE_DIVIDE(purchasers, sessions) AS cvr,
  SAFE_DIVIDE(revenue, purchasers) AS avg_order_value
FROM monthly_data;
