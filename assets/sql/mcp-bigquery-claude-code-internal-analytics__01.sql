-- 出典: MCP × BigQuery × Claude Codeで聞くだけで分析できる社内ツールを作った
-- 記事: articles/mcp-bigquery-claude-code-internal-analytics.md（例1：チャネル別セッション数の確認）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  channel_grouping,
  COUNT(DISTINCT session_id) AS sessions
FROM `${PROJECT}.${DATASET}.stg_sessions`
WHERE session_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) AND CURRENT_DATE()
GROUP BY channel_grouping
ORDER BY sessions DESC
