-- ECのセール施策効果をGA4×BigQueryでbefore/after比較する分析テンプレート
-- 用途: SQLテンプレート：セール前後の主要KPIを比較する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH
-- 期間ラベルを付与するベーステーブル
base AS (
  SELECT
    event_date,
    event_name,
    CASE
      WHEN event_date BETWEEN '20250601' AND '20250614' THEN 'before'
      WHEN event_date BETWEEN '20250615' AND '20250621' THEN 'during'
      WHEN event_date BETWEEN '20250622' AND '20250705' THEN 'after'
      ELSE NULL
    END AS period,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS session_id,
    (SELECT value.double_value
     FROM UNNEST(event_params)
     WHERE key = 'value') AS purchase_value
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250705'
),

-- セッション単位に集約
sessions AS (
  SELECT
    period,
    session_id,
    COUNTIF(event_name = 'purchase') AS purchase_count,
    SUM(IF(event_name = 'purchase', purchase_value, 0)) AS revenue
  FROM base
  WHERE period IS NOT NULL
    AND session_id IS NOT NULL
  GROUP BY period, session_id
)

-- 期間別KPIの集計
SELECT
  period,
  COUNT(DISTINCT session_id)                        AS sessions,
  SUM(purchase_count)                               AS purchases,
  ROUND(SUM(purchase_count) / COUNT(DISTINCT session_id) * 100, 2) AS conversion_rate_pct,
  ROUND(SUM(revenue), 0)                            AS total_revenue
FROM sessions
GROUP BY period
ORDER BY
  CASE period WHEN 'before' THEN 1 WHEN 'during' THEN 2 WHEN 'after' THEN 3 END
;
