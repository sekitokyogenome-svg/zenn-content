-- BigQuery MLの需要予測モデルでEC仕入れ量を最適化する実装手順
-- 用途: ARIMA_PLUSモデルの構築手順
-- 必要テーブル: daily_sales_summary, demand_forecast_model
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE MODEL `${PROJECT}.${DATASET}.demand_forecast_model`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'date',
  time_series_data_col = 'units_sold',
  auto_arima = TRUE,
  data_frequency = 'DAILY',
  decompose_time_series = TRUE,
  holiday_region = 'JP'
) AS
SELECT
  date,
  units_sold
FROM
  `${PROJECT}.${DATASET}.daily_sales_summary`
WHERE
  date BETWEEN '2023-01-01' AND '2024-12-31'
ORDER BY
  date;
