-- GA4×BigQueryでECサイトの速度改善がCVRに与えた影響を測定した
-- 用途: Step 2: LCPとCVRの相関分析
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH user_lcp AS (
  SELECT
    user_pseudo_id,
    APPROX_QUANTILES(
      (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'metric_value'),
      100
    )[OFFSET(50)] AS median_lcp
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'web_vitals'
    AND (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'metric_name') = 'LCP'
  GROUP BY user_pseudo_id
),
user_conversions AS (
  SELECT
    user_pseudo_id,
    COUNTIF(event_name = 'purchase') AS purchases
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  GROUP BY user_pseudo_id
),
combined AS (
  SELECT
    l.user_pseudo_id,
    l.median_lcp,
    CASE
      WHEN l.median_lcp <= 2500 THEN '良好（2.5秒以下）'
      WHEN l.median_lcp <= 4000 THEN '改善が必要（2.5-4秒）'
      ELSE '不良（4秒超）'
    END AS lcp_category,
    IFNULL(c.purchases, 0) AS purchases,
    IF(IFNULL(c.purchases, 0) > 0, 1, 0) AS converted
  FROM user_lcp l
  LEFT JOIN user_conversions c
    ON l.user_pseudo_id = c.user_pseudo_id
)
SELECT
  lcp_category,
  COUNT(*) AS users,
  SUM(converted) AS converters,
  ROUND(SUM(converted) / COUNT(*) * 100, 2) AS cvr_pct
FROM combined
GROUP BY lcp_category
ORDER BY cvr_pct DESC
