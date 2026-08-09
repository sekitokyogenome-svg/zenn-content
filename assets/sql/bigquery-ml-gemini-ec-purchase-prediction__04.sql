-- 出典: BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する
-- 記事: articles/bigquery-ml-gemini-ec-purchase-prediction.md（BigQuery MLでロジスティック回帰モデルを訓練する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT *
FROM ML.EVALUATE(MODEL `${PROJECT}.${DATASET}.purchase_prediction_model`);
