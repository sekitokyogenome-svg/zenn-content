-- BigQuery × Looker Studioで広告媒体横断ROASダッシュボードを構築する全手順
-- 用途: 4. BigQueryで統合ビューを作成する
-- 必要テーブル: ad_cost, events_*, v_roas_summary
-- コスト: `_TABLE_SUFFIX` の条件が無いため全期間をスキャンします。期間を絞ってください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE VIEW `${PROJECT}.${DATASET}.v_roas_summary` AS

WITH ga4_revenue AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS date,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    SUM(ecommerce.purchase_revenue) AS revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    1, 2, 3
),

ad_cost AS (
  SELECT
    date,
    medium,
    source,
    SUM(cost) AS cost
  FROM
    `${PROJECT}.${DATASET}.ad_cost`
  GROUP BY
    1, 2, 3
)

SELECT
  COALESCE(r.date, c.date) AS date,
  COALESCE(r.medium, c.medium) AS medium,
  COALESCE(r.source, c.source) AS source,
  COALESCE(r.revenue, 0) AS revenue,
  COALESCE(c.cost, 0) AS cost,
  SAFE_DIVIDE(COALESCE(r.revenue, 0), COALESCE(c.cost, 0)) AS roas
FROM
  ga4_revenue r
FULL OUTER JOIN
  ad_cost c
  ON r.date = c.date
  AND r.medium = c.medium
  AND r.source = c.source
