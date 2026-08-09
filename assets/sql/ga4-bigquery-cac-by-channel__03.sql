-- 出典: GA4×BigQueryでEC新規顧客獲得コスト（CAC）を媒体別に正確計算する
-- 記事: articles/ga4-bigquery-cac-by-channel.md（方法2: Google Sheetsを外部テーブルとして使う）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- Google Sheetsの外部テーブルを事前に作成しておく
-- CREATE EXTERNAL TABLE `your-project.ad_costs.monthly_costs`
-- OPTIONS (
--   format = 'GOOGLE_SHEETS',
--   uris = ['https://docs.google.com/spreadsheets/d/XXXXX']
-- )

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
