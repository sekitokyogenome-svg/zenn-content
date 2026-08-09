-- 出典: Claude CodeのAgentモードでEC売上データを自動分析させた結果
-- 記事: articles/claude-code-agent-mode-ec-sales-analysis.md（Step 1: BigQueryクエリの自動生成）
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
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  date, medium
ORDER BY
  date DESC, revenue DESC
