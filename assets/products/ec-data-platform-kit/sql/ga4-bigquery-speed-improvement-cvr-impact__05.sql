-- GA4×BigQueryでECサイトの速度改善がCVRに与えた影響を測定した
-- 用途: Step 4: デバイス別の速度×CVR分析
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH device_performance AS (
  SELECT
    device.category AS device_category,
    CASE
      WHEN (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value') <= 2500 THEN '良好'
      WHEN (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value') <= 4000 THEN '要改善'
      ELSE '不良'
    END AS lcp_status,
    user_pseudo_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'web_vitals'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'metric_name') = 'LCP'
),
device_conversions AS (
  SELECT
    user_pseudo_id,
    1 AS converted
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)
SELECT
  dp.device_category,
  dp.lcp_status,
  COUNT(DISTINCT dp.user_pseudo_id) AS users,
  COUNTIF(dc.converted = 1) AS converters,
  ROUND(COUNTIF(dc.converted = 1) / COUNT(DISTINCT dp.user_pseudo_id) * 100, 2) AS cvr_pct
FROM device_performance dp
LEFT JOIN device_conversions dc
  ON dp.user_pseudo_id = dc.user_pseudo_id
GROUP BY dp.device_category, dp.lcp_status
ORDER BY dp.device_category, dp.lcp_status
