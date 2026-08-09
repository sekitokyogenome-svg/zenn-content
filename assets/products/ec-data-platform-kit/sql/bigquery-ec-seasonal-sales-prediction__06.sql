-- BigQueryでEC季節商品の売上予測モデルを作った話
-- 用途: 線形回帰モデルとの比較
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE MODEL `your-project.mart.sales_linear_model`
OPTIONS (
  model_type = 'LINEAR_REG',
  input_label_cols = ['daily_revenue']
) AS
SELECT
  daily_revenue,
  EXTRACT(MONTH FROM sale_date) AS month,
  EXTRACT(DAYOFWEEK FROM sale_date) AS day_of_week,
  CASE
    WHEN EXTRACT(MONTH FROM sale_date) IN (12, 1, 7, 8) THEN 1
    ELSE 0
  END AS is_peak_season,
  unique_buyers,
  transaction_count
FROM `your-project.mart.daily_sales`
WHERE sale_date BETWEEN '2024-01-01' AND '2025-12-31'
