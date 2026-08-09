-- 303. ECのセール施策効果をGA4×BigQueryでbefore/after比較する分析テンプレート（流入元別の効果測定：どのチャネルがセール集客に貢献したか）
-- 用途: 流入元別の効果測定：どのチャネルがセール集客に貢献したか
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH
session_source AS (
  SELECT
    event_date,
    event_name,
    CASE
      WHEN event_date BETWEEN '20250615' AND '20250621' THEN 'during'
      ELSE NULL
    END AS period,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    (SELECT value.double_value
     FROM UNNEST(event_params)
     WHERE key = 'value') AS purchase_value
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250615' AND '20250621'
),

sessions_agg AS (
  SELECT
    period,
    session_id,
    -- セッション最初の流入元を使用（first_valueで代替も可）
    MAX(medium) AS medium,
    MAX(source) AS source,
    COUNTIF(event_name = 'purchase') AS purchase_count,
    SUM(IF(event_name = 'purchase', purchase_value, 0)) AS revenue
  FROM session_source
  WHERE period IS NOT NULL
    AND session_id IS NOT NULL
  GROUP BY period, session_id
)

SELECT
  COALESCE(medium, '(none)')  AS medium,
  COALESCE(source, '(direct)') AS source,
  COUNT(DISTINCT session_id)   AS sessions,
  SUM(purchase_count)          AS purchases,
  ROUND(SUM(purchase_count) / COUNT(DISTINCT session_id) * 100, 2) AS cvr_pct,
  ROUND(SUM(revenue), 0)       AS revenue
FROM sessions_agg
GROUP BY medium, source
ORDER BY revenue DESC
LIMIT 20
;
