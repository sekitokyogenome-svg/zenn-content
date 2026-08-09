-- 48. BigQuery ML × 時系列モデルARIMA_PLUSでEC売上の週次予測を自動化する（ステップ3: 予測結果を取得する）
-- 用途: ステップ3: 予測結果を取得する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  forecast_timestamp AS week_start,
  ROUND(forecast_value, 0) AS predicted_revenue,
  ROUND(prediction_interval_lower_bound, 0) AS lower_bound,
  ROUND(prediction_interval_upper_bound, 0) AS upper_bound
FROM
  ML.FORECAST(
    MODEL `${PROJECT}.${DATASET}.ec_weekly_forecast_model`,
    STRUCT(8 AS horizon, 0.9 AS confidence_level)
  )
ORDER BY
  forecast_timestamp ASC;
