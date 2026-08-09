-- GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する
-- 用途: 方法2: Google Sheetsを外部テーブルとして使う
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
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
