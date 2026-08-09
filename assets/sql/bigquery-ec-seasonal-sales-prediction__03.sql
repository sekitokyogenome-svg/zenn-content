-- 出典: BigQueryでEC季節商品の売上予測モデルを作った話
-- 記事: articles/bigquery-ec-seasonal-sales-prediction.md（Step 3: モデルの評価）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  *
FROM
  ML.ARIMA_EVALUATE(MODEL `your-project.mart.sales_forecast_model`)
