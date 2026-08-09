-- 出典: BigQuery × Looker Studioで前年同期比グラフを作る方法
-- 記事: articles/bigquery-looker-studio-yoy-comparison-chart.md（月別集計パターン）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH monthly_data AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), MONTH) AS month,
    EXTRACT(YEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS year,
    EXTRACT(MONTH FROM PARSE_DATE('%Y%m%d', event_date)) AS month_num,
    SUM(ecommerce.purchase_revenue) AS revenue,
    COUNTIF(event_name = 'purchase') AS purchases
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 24 MONTH))
  GROUP BY month, year, month_num
)

SELECT
  cy.month,
  cy.month_num,
  cy.revenue AS revenue_current_year,
  ly.revenue AS revenue_last_year,
  SAFE_DIVIDE(cy.revenue - ly.revenue, ly.revenue) * 100 AS yoy_change_pct
FROM
  monthly_data cy
LEFT JOIN
  monthly_data ly
  ON cy.month_num = ly.month_num
  AND cy.year = ly.year + 1
WHERE
  cy.year = EXTRACT(YEAR FROM CURRENT_DATE())
ORDER BY
  cy.month_num
