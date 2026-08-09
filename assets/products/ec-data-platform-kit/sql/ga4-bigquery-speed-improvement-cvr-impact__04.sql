-- GA4×BigQueryでECサイトの速度改善がCVRに与えた影響を測定した
-- 用途: Step 3: 速度改善前後の比較
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH period_metrics AS (
  SELECT
    CASE
      WHEN DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')
        BETWEEN '2025-06-01' AND '2025-06-30' THEN '改善前（6月）'
      WHEN DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo')
        BETWEEN '2025-08-01' AND '2025-08-31' THEN '改善後（8月）'
    END AS period,
    event_name,
    user_pseudo_id,
    (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value') AS lcp_value,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'metric_name') AS metric_name
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250831'
    AND (
      event_name = 'web_vitals'
      OR event_name = 'purchase'
      OR event_name = 'session_start'
    )
),
lcp_summary AS (
  SELECT
    period,
    ROUND(APPROX_QUANTILES(lcp_value, 100)[OFFSET(75)], 0) AS lcp_p75
  FROM period_metrics
  WHERE metric_name = 'LCP'
    AND period IS NOT NULL
  GROUP BY period
),
cvr_summary AS (
  SELECT
    period,
    COUNT(DISTINCT CASE WHEN event_name = 'session_start' THEN user_pseudo_id END) AS sessions,
    COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_pseudo_id END) AS purchasers,
    ROUND(
      COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN user_pseudo_id END)
      / COUNT(DISTINCT CASE WHEN event_name = 'session_start' THEN user_pseudo_id END) * 100,
      2
    ) AS cvr_pct
  FROM period_metrics
  WHERE period IS NOT NULL
  GROUP BY period
)
SELECT
  c.period,
  l.lcp_p75,
  c.sessions,
  c.purchasers,
  c.cvr_pct
FROM cvr_summary c
INNER JOIN lcp_summary l
  ON c.period = l.period
ORDER BY c.period
