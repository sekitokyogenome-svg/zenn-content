-- 出典: BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する
-- 記事: articles/bigquery-ml-gemini-ec-purchase-prediction.md（GeminiでセグメントのインサイトをAIに言語化させる）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

CREATE OR REPLACE MODEL `${PROJECT}.${DATASET}.gemini_model`
REMOTE WITH CONNECTION `your_project.your_region.your_connection`
OPTIONS (endpoint = 'gemini-1.5-flash');
