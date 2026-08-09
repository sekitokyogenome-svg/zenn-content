-- 47. BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する（商品データをBigQueryに格納する）
-- 用途: 商品データをBigQueryに格納する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE TABLE `your_project.ec_dataset.products` (
  product_id   STRING,
  product_name STRING,
  category     STRING,
  description  STRING
);
