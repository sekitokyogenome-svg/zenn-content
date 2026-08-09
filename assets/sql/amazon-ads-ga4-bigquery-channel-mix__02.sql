-- 出典: Amazon広告とGA4自社ECデータをBigQueryで統合してチャネルミックスを最適化する
-- 記事: articles/amazon-ads-ga4-bigquery-channel-mix.md（Amazon広告データとGA4データをBigQueryで結合する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH amazon_summary AS (
  SELECT
    report_date,
    SUM(spend) AS amazon_spend,
    SUM(sales_14d) AS amazon_revenue,
    SUM(clicks) AS amazon_clicks,
    SUM(impressions) AS amazon_impressions
  FROM
    `${PROJECT}.${DATASET}.amazon_ads_campaign_report`
  GROUP BY
    report_date
),

ga4_paid AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_date,
    SUM(
      CASE
        WHEN event_name = 'purchase'
        THEN (
          SELECT value.double_value
          FROM UNNEST(event_params) AS ep
          WHERE ep.key = 'value'
        )
        ELSE 0
      END
    ) AS own_ec_revenue,
    COUNTIF(event_name = 'purchase') AS own_ec_purchases
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
    AND collected_traffic_source.manual_medium IN ('cpc', 'paid', 'ppc')
  GROUP BY
    event_date
)

SELECT
  COALESCE(a.report_date, g.event_date) AS date,
  COALESCE(a.amazon_spend, 0) AS amazon_spend,
  COALESCE(a.amazon_revenue, 0) AS amazon_revenue,
  COALESCE(g.own_ec_revenue, 0) AS own_ec_revenue,
  COALESCE(a.amazon_revenue, 0) + COALESCE(g.own_ec_revenue, 0) AS total_revenue
FROM
  amazon_summary a
FULL OUTER JOIN
  ga4_paid g
ON
  a.report_date = g.event_date
ORDER BY
  date
