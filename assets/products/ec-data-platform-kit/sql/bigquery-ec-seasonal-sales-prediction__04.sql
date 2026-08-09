-- BigQueryでEC季節商品の売上予測モデルを作った話
-- 用途: Step 4: 売上予測の実行
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  forecast_timestamp AS predicted_date,
  forecast_value AS predicted_revenue,
  prediction_interval_lower_bound AS lower_bound,
  prediction_interval_upper_bound AS upper_bound
FROM
  ML.FORECAST(
    MODEL `your-project.mart.sales_forecast_model`,
    STRUCT(90 AS horizon, 0.95 AS confidence_level)
  )
ORDER BY forecast_timestamp
