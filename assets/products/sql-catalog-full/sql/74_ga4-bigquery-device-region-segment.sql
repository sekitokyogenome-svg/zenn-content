-- 74. GA4×BigQueryでデバイス別・地域別セグメント分析をする（デバイス別セッション数・コンバージョン率）
-- 用途: デバイス別セッション数・コンバージョン率
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH sessions AS (
  SELECT
    CONCAT(
      user_pseudo_id, '.',
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id,
    device.category AS device_category,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
),
session_summary AS (
  SELECT
    session_id,
    device_category,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
  FROM sessions
  GROUP BY session_id, device_category
)
SELECT
  device_category,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS cv_sessions,
  ROUND(SUM(has_purchase) / COUNT(*) * 100, 2) AS cv_rate_percent
FROM session_summary
GROUP BY device_category
ORDER BY sessions DESC
