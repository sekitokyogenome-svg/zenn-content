-- 165. MCP × BigQuery × Claude Codeで聞くだけで分析できる社内ツールを作った
-- 用途: 例1：チャネル別セッション数の確認
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  channel_grouping,
  COUNT(DISTINCT session_id) AS sessions
FROM `${PROJECT}.${DATASET}.stg_sessions`
WHERE session_date BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY) AND CURRENT_DATE()
GROUP BY channel_grouping
ORDER BY sessions DESC
