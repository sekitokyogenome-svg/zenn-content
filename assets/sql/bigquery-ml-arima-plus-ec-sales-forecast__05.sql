-- 出典: BigQuery ML × 時系列モデルARIMA_PLUSでEC売上の週次予測を自動化する
-- 記事: articles/bigquery-ml-arima-plus-ec-sales-forecast.md（ステップ4: 予測精度を評価する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  mean_absolute_error,
  mean_squared_error,
  root_mean_squared_error,
  mean_absolute_percentage_error,
  symmetric_mean_absolute_percentage_error
FROM
  ML.EVALUATE(MODEL `${PROJECT}.${DATASET}.ec_weekly_forecast_model`);
