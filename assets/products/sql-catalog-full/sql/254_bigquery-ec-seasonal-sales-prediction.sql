-- 254. BigQueryでEC季節商品の売上予測モデルを作った話（Step 2: ARIMA_PLUSモデルの作成）
-- 用途: Step 2: ARIMA_PLUSモデルの作成
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE MODEL `your-project.mart.sales_forecast_model`
OPTIONS (
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'sale_date',
  time_series_data_col = 'daily_revenue',
  auto_arima = TRUE,
  data_frequency = 'DAILY',
  holiday_region = 'JP'
) AS
SELECT
  sale_date,
  daily_revenue
FROM
  `your-project.mart.daily_sales`
WHERE
  sale_date BETWEEN '2024-01-01' AND '2025-12-31'
