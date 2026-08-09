-- BigQueryでEC季節商品の売上予測モデルを作った話
-- 用途: Step 5: 予測精度の検証（バックテスト）
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE MODEL `your-project.mart.sales_forecast_backtest`
OPTIONS (
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'sale_date',
  time_series_data_col = 'daily_revenue',
  auto_arima = TRUE,
  data_frequency = 'DAILY',
  holiday_region = 'JP'
) AS
SELECT sale_date, daily_revenue
FROM `your-project.mart.daily_sales`
WHERE sale_date BETWEEN '2024-01-01' AND '2025-09-30';

-- 予測と実績の比較
WITH forecast AS (
  SELECT
    forecast_timestamp AS predicted_date,
    forecast_value AS predicted_revenue
  FROM ML.FORECAST(
    MODEL `your-project.mart.sales_forecast_backtest`,
    STRUCT(92 AS horizon, 0.95 AS confidence_level)
  )
),
actual AS (
  SELECT
    sale_date,
    daily_revenue AS actual_revenue
  FROM `your-project.mart.daily_sales`
  WHERE sale_date BETWEEN '2025-10-01' AND '2025-12-31'
)
SELECT
  a.sale_date,
  a.actual_revenue,
  f.predicted_revenue,
  ROUND(ABS(a.actual_revenue - f.predicted_revenue) / a.actual_revenue * 100, 1) AS error_pct
FROM actual a
INNER JOIN forecast f
  ON a.sale_date = DATE(f.predicted_date)
ORDER BY a.sale_date
