-- 152. BigQuery × Claude Codeで月次事業報告書を自動作成する仕組み（チャネル別パフォーマンス）
-- 用途: チャネル別パフォーマンス
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  CONCAT(
    IFNULL(collected_traffic_source.manual_source, '(direct)'),
    ' / ',
    IFNULL(collected_traffic_source.manual_medium, '(none)')
  ) AS channel,
  COUNT(DISTINCT CONCAT(
    user_pseudo_id,
    CAST((SELECT value.int_value FROM UNNEST(event_params)
          WHERE key = 'ga_session_id') AS STRING)
  )) AS sessions,
  SUM(CASE WHEN event_name = 'purchase'
    THEN ecommerce.purchase_revenue ELSE 0 END) AS revenue
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE('%Y%m%d', DATE_TRUNC(
    DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
  AND FORMAT_DATE('%Y%m%d', LAST_DAY(
    DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
GROUP BY channel
ORDER BY sessions DESC
LIMIT 10;
