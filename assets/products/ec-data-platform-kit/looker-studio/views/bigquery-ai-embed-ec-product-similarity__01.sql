-- BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する
-- 出典: articles/bigquery-ai-embed-ec-product-similarity.md

CREATE OR REPLACE TABLE `your_project.ec_dataset.products` (
  product_id   STRING,
  product_name STRING,
  category     STRING,
  description  STRING
);
