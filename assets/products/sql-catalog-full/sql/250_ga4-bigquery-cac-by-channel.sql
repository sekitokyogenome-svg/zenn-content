-- 250. GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する（方法2: Google Sheetsを外部テーブルとして使う）
-- 用途: 方法2: Google Sheetsを外部テーブルとして使う
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  nc.channel,
  nc.source,
  nc.new_customers,
  ac.cost AS monthly_cost,
  ROUND(ac.cost / NULLIF(nc.new_customers, 0), 0) AS cac
FROM new_customers_by_source nc
INNER JOIN `your-project.ad_costs.monthly_costs` ac
  ON nc.channel = ac.channel AND nc.source = ac.source
ORDER BY cac
