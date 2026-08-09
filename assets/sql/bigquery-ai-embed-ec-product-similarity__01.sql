-- 出典: BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する
-- 記事: articles/bigquery-ai-embed-ec-product-similarity.md（商品データをBigQueryに格納する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 商品マスタテーブルの作成例
CREATE OR REPLACE TABLE `your_project.ec_dataset.products` (
  product_id   STRING,
  product_name STRING,
  category     STRING,
  description  STRING
);
