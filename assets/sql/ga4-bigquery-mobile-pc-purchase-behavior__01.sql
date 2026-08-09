-- 出典: GA4×BigQueryでモバイルとPCの購買行動の違いを分析した
-- 記事: articles/ga4-bigquery-mobile-pc-purchase-behavior.md（デバイス別の基本指標を比較する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH sessions AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    device.category AS device_category
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'session_start'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
),
purchases AS (
  SELECT DISTINCT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name = 'purchase'
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  s.device_category,
  COUNT(DISTINCT CONCAT(s.user_pseudo_id, '-', CAST(s.ga_session_id AS STRING))) AS sessions,
  COUNT(DISTINCT CONCAT(p.user_pseudo_id, '-', CAST(p.ga_session_id AS STRING))) AS purchase_sessions,
  ROUND(
    SAFE_DIVIDE(
      COUNT(DISTINCT CONCAT(p.user_pseudo_id, '-', CAST(p.ga_session_id AS STRING))),
      COUNT(DISTINCT CONCAT(s.user_pseudo_id, '-', CAST(s.ga_session_id AS STRING)))
    ) * 100, 2
  ) AS cvr
FROM sessions s
LEFT JOIN purchases p
  ON s.user_pseudo_id = p.user_pseudo_id
  AND s.ga_session_id = p.ga_session_id
GROUP BY s.device_category
ORDER BY sessions DESC;
