-- 出典: Looker StudioのブレンディングでGA4×広告データを結合する方法
-- 記事: articles/looker-studio-blending-ga4-ads-data.md（GA4とGoogle広告を結合するSQL）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH ga4_daily AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )) AS sessions,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))
  GROUP BY
    date
),

ads_daily AS (
  SELECT
    segments_date AS date,
    SUM(metrics_cost_micros / 1000000) AS ad_cost,
    SUM(metrics_clicks) AS ad_clicks,
    SUM(metrics_impressions) AS ad_impressions
  FROM
    `${PROJECT}.${DATASET}.p_CampaignStats_XXXXXXX`
  GROUP BY
    date
)

SELECT
  g.date,
  g.sessions,
  g.purchases,
  g.revenue,
  a.ad_cost,
  a.ad_clicks,
  a.ad_impressions,
  SAFE_DIVIDE(g.revenue, a.ad_cost) AS roas,
  SAFE_DIVIDE(a.ad_cost, g.purchases) AS cpa
FROM
  ga4_daily g
LEFT JOIN
  ads_daily a ON g.date = a.date
ORDER BY
  g.date DESC;
