-- 出典: BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する
-- 記事: articles/bigquery-ml-gemini-ec-purchase-prediction.md（特徴量テーブルを作成する（GA4エクスポートデータの加工））
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.ec_user_features` AS
-- 上記のSELECT文をそのまま貼り付けてください
;
