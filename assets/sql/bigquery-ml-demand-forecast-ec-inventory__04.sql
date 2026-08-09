-- 出典: BigQuery MLの需要予測モデルでEC仕入れ量を最適化する実装手順
-- 記事: articles/bigquery-ml-demand-forecast-ec-inventory.md（予測結果を仕入れ計画に反映する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  forecast_timestamp,
  forecast_value,
  prediction_interval_lower_bound,
  prediction_interval_upper_bound
FROM
  ML.FORECAST(
    MODEL `${PROJECT}.${DATASET}.demand_forecast_model`,
    STRUCT(30 AS horizon, 0.9 AS confidence_level)
  )
ORDER BY
  forecast_timestamp;
