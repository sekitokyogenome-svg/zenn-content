-- 236. 中小ECのLTV分析をGA4×BigQueryで無料構築する方法【SQLテンプレ付き】（LTVを意思決定に活用する: LTV:CAC比率）
-- 用途: LTVを意思決定に活用する: LTV:CAC比率
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH user_first_session AS (
  SELECT
    user_pseudo_id,
    collected_traffic_source.manual_medium AS first_medium,
    collected_traffic_source.manual_source AS first_source,
    MIN(event_timestamp) AS first_event_timestamp
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    collected_traffic_source.manual_medium IS NOT NULL
  GROUP BY
    user_pseudo_id,
    collected_traffic_source.manual_medium,
    collected_traffic_source.manual_source
),
user_revenue AS (
  SELECT
    user_pseudo_id,
    SUM(ecommerce.purchase_revenue) AS total_revenue,
    COUNT(*) AS purchase_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    user_pseudo_id
)
SELECT
  fs.first_medium,
  fs.first_source,
  COUNT(DISTINCT ur.user_pseudo_id) AS paying_users,
  ROUND(AVG(ur.total_revenue), 0) AS avg_ltv,
  ROUND(AVG(ur.purchase_count), 1) AS avg_purchase_count
FROM
  user_first_session fs
INNER JOIN
  user_revenue ur ON fs.user_pseudo_id = ur.user_pseudo_id
GROUP BY
  fs.first_medium, fs.first_source
HAVING
  COUNT(DISTINCT ur.user_pseudo_id) >= 10  -- サンプル数が少なすぎるチャネルを除外
ORDER BY
  avg_ltv DESC
