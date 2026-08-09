-- 232. BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った（原価データとの結合で粗利を算出する） その1
-- 用途: 原価データとの結合で粗利を算出する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH product_performance AS (
  -- 前述のクエリ結果（item_id, view_sessions, purchase_sessions, cvr, total_revenue）
  SELECT * FROM product_cvr_data
),
product_profit AS (
  SELECT
    pp.item_id,
    pp.item_name,
    pp.view_sessions,
    pp.purchase_sessions,
    pp.cvr,
    pp.total_revenue,
    pc.cost_price,
    pc.selling_price,
    ROUND(pp.total_revenue - (pc.cost_price * pp.purchase_sessions), 0) AS gross_profit,
    ROUND(
      SAFE_DIVIDE(
        pp.total_revenue - (pc.cost_price * pp.purchase_sessions),
        pp.total_revenue
      ) * 100, 1
    ) AS gross_margin_pct
  FROM product_performance pp
  LEFT JOIN `${PROJECT}.${DATASET}.product_cost` pc
    ON pp.item_id = pc.item_id
)
SELECT
  item_id,
  item_name,
  view_sessions,
  purchase_sessions,
  cvr,
  total_revenue,
  gross_profit,
  gross_margin_pct,
  ROUND(SAFE_DIVIDE(gross_profit, view_sessions), 0) AS profit_per_view
FROM product_profit
ORDER BY gross_profit DESC;
