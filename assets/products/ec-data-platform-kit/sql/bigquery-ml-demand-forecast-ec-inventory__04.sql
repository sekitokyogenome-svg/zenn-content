-- BigQuery MLの需要予測モデルでEC仕入れ量を最適化する実装手順
-- 用途: 予測結果を仕入れ計画に反映する
-- 必要テーブル: demand_forecast_model
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
