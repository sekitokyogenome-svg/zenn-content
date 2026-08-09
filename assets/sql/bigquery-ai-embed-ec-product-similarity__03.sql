-- 出典: BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する
-- 記事: articles/bigquery-ai-embed-ec-product-similarity.md（AI.EMBEDで商品ベクトルを生成する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- Vertex AI接続モデルの登録（初回のみ）
CREATE OR REPLACE MODEL `your_project.ec_dataset.embedding_model`
REMOTE WITH CONNECTION `your_project.us.vertex-ai-connection`
OPTIONS (ENDPOINT = 'text-embedding-004');
