-- 出典: Claude Code × Gemini CLIをオーケストレーションしてEC分析を多角的に回す方法
-- 記事: articles/claude-code-gemini-cli-orchestration-ec.md（GA4 BigQueryエクスポートでEC分析に必要なSQL基礎）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- GA4 BigQuery: セッション別流入元×購買フラグ集計
WITH session_base AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase,
    SUM(IF(event_name = 'purchase',
      (SELECT value.double_value
       FROM UNNEST(event_params)
       WHERE key = 'value'), 0)) AS purchase_value
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
  GROUP BY
    user_pseudo_id,
    ga_session_id,
    medium,
    source
)
SELECT
  source,
  medium,
  COUNT(DISTINCT ga_session_id) AS sessions,
  SUM(has_purchase) AS purchases,
  ROUND(SUM(purchase_value), 0) AS total_revenue,
  ROUND(SAFE_DIVIDE(SUM(has_purchase), COUNT(DISTINCT ga_session_id)) * 100, 2) AS cvr_pct
FROM session_base
GROUP BY source, medium
ORDER BY total_revenue DESC
LIMIT 20;
