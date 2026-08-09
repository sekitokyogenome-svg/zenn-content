-- 38. BigQuery ML × 時系列モデルARIMA_PLUSでEC売上の週次予測を自動化する（ステップ2: ARIMA_PLUSモデルを学習させる）
-- 用途: ステップ2: ARIMA_PLUSモデルを学習させる
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE MODEL
  `${PROJECT}.${DATASET}.ec_weekly_forecast_model`
OPTIONS(
  model_type = 'ARIMA_PLUS',
  time_series_timestamp_col = 'week_start',
  time_series_data_col = 'weekly_revenue',
  data_frequency = 'WEEKLY',
  horizon = 8,
  holiday_region = 'JP'
) AS
SELECT
  week_start,
  weekly_revenue
FROM
  `${PROJECT}.${DATASET}.weekly_revenue_summary`
WHERE
  weekly_revenue IS NOT NULL;
