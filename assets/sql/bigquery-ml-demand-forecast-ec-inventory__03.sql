-- 出典: BigQuery MLの需要予測モデルでEC仕入れ量を最適化する実装手順
-- 記事: articles/bigquery-ml-demand-forecast-ec-inventory.md（ARIMA_PLUSモデルの構築手順）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT *
FROM ML.EVALUATE(MODEL `${PROJECT}.${DATASET}.demand_forecast_model`);
