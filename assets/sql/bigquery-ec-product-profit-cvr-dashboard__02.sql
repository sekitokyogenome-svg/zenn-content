-- 出典: BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った
-- 記事: articles/bigquery-ec-product-profit-cvr-dashboard.md（原価データとの結合で粗利を算出する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 原価テーブルの想定スキーマ
-- スプレッドシートまたはCSVからBigQueryにインポートする
CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.product_cost` (
  item_id STRING,
  item_name STRING,
  cost_price FLOAT64,
  selling_price FLOAT64
);
