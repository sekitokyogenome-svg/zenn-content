-- 32. Claude CodeのAgents SDKでEC在庫アラート→発注提案→Slack通知を全自動化した
-- 用途: BigQuery での在庫 × 売上集計 SQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH
-- GA4 から直近 7 日間の商品別注文数を集計
ga4_sales AS (
  SELECT
    ep_item.value.string_value AS item_id,
    COUNT(DISTINCT
      (SELECT ep.value.int_value
       FROM UNNEST(event_params) AS ep
       WHERE ep.key = 'ga_session_id')
    ) AS session_count,
    SUM(ecommerce.purchase_revenue) AS revenue_7d,
    -- 流入元の確認
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS ep_item
  WHERE
    _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
      AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'purchase'
  GROUP BY
    item_id, medium, source
),

-- 在庫テーブル（例: Shopify エクスポート or 自社 DB を BQ に同期）
inventory AS (
  SELECT
    product_id,
    product_name,
    stock_quantity,
    reorder_point,
    lead_time_days
  FROM
    `your_project.ec_data.inventory_snapshot`
  WHERE
    snapshot_date = CURRENT_DATE()
)

SELECT
  i.product_id,
  i.product_name,
  i.stock_quantity,
  i.reorder_point,
  i.lead_time_days,
  COALESCE(s.session_count, 0)             AS sessions_7d,
  COALESCE(s.revenue_7d, 0)               AS revenue_7d,
  -- 1日平均販売数（セッション数を粗い代理変数として使用）
  ROUND(COALESCE(s.session_count, 0) / 7, 1) AS avg_daily_sales,
  -- 在庫残日数の推定
  CASE
    WHEN COALESCE(s.session_count, 0) = 0 THEN 999
    ELSE ROUND(i.stock_quantity / (s.session_count / 7), 0)
  END AS estimated_days_remaining
FROM
  inventory AS i
LEFT JOIN
  ga4_sales AS s
  ON i.product_id = s.item_id
WHERE
  -- 在庫残日数がリードタイム以下の商品のみ抽出
  CASE
    WHEN COALESCE(s.session_count, 0) = 0 THEN 999
    ELSE ROUND(i.stock_quantity / (s.session_count / 7), 0)
  END <= i.lead_time_days
ORDER BY
  estimated_days_remaining ASC
LIMIT 20
