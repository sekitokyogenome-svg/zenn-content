-- 出典: BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する
-- 記事: articles/bigquery-ai-embed-ec-product-similarity.md（AI.EMBEDで商品ベクトルを生成する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 商品ベクトルテーブルの作成
CREATE OR REPLACE TABLE `your_project.ec_dataset.product_embeddings` AS
SELECT
  product_id,
  product_name,
  category,
  ml_generate_embedding_result AS embedding
FROM
  ML.GENERATE_EMBEDDING(
    MODEL `your_project.ec_dataset.embedding_model`,
    (
      SELECT
        product_id,
        product_name,
        category,
        CONCAT(product_name, ' ', category, ' ', description) AS content
      FROM
        `your_project.ec_dataset.products`
    ),
    STRUCT(TRUE AS flatten_json_output)
  );
