-- 出典: Claude Code × Google Sheets APIでBigQueryレポートを自動更新する
-- 記事: articles/claude-code-sheets-api-bigquery-report.md（Step 2: BigQueryからデータを取得するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `{project_id}.{dataset}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  date, medium
ORDER BY
  date DESC, revenue DESC
