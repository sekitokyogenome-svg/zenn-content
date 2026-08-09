-- 出典: BigQuery MLの需要予測モデルでEC仕入れ量を最適化する実装手順
-- 記事: articles/bigquery-ml-demand-forecast-ec-inventory.md（ARIMA_PLUSモデルの構築手順）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
