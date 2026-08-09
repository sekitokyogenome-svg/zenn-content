-- 出典: Claude Code × BigQuery MCPでGA4分析を完全自動化する方法【EC事業者向け実践ガイド】
-- 記事: articles/claude-code-bigquery-mcp-ga4.md（ケース1：チャネル別セッション数・CV数の確認）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  collected_traffic_source.manual_medium AS medium,
  COUNT(DISTINCT
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING))
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS conversions,
  ROUND(
    COUNTIF(event_name = 'purchase') /
    COUNT(DISTINCT
      CONCAT(user_pseudo_id, CAST(
        (SELECT value.int_value FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING))
    ) * 100, 2
  ) AS cvr_pct
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN
  FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
  AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
GROUP BY 1
ORDER BY sessions DESC
