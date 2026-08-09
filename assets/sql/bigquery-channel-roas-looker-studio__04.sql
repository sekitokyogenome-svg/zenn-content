-- 出典: チャネル別ROASをBigQueryで集計してLooker Studioに可視化する
-- 記事: articles/bigquery-channel-roas-looker-studio.md（Step 4：マートテーブルに保存する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- マートビューとして作成
CREATE OR REPLACE VIEW `project.dataset_mart.mart_channel_roas` AS
WITH channel_revenue AS (
  SELECT
    FORMAT_DATE('%Y-%m', PARSE_DATE('%Y%m%d', event_date)) AS month,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNTIF(event_name = 'purchase') AS purchases,
    SUM(
      IF(event_name = 'purchase', ecommerce.purchase_revenue, 0)
    ) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND collected_traffic_source.manual_medium IS NOT NULL
  GROUP BY
    month, medium, source
),
channel_spend AS (
  SELECT month, medium, source, spend
  FROM `${PROJECT}.${DATASET}.ad_spend`
)
SELECT
  r.month,
  r.medium,
  r.source,
  r.users,
  r.purchases,
  r.revenue,
  COALESCE(s.spend, 0) AS spend,
  SAFE_DIVIDE(r.revenue, s.spend) * 100 AS roas_pct,
  SAFE_DIVIDE(s.spend, r.purchases) AS cpa
FROM
  channel_revenue r
LEFT JOIN
  channel_spend s
  ON r.month = s.month
  AND r.medium = s.medium
  AND r.source = s.source;
