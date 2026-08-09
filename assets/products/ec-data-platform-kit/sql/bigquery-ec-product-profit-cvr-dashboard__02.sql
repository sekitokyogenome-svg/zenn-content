-- BigQueryでEC商品別の粗利×CVR×流入数をまとめた利益ダッシュボードを作った
-- 用途: 原価データとの結合で粗利を算出する
-- 必要テーブル: product_cost
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.product_cost` (
  item_id STRING,
  item_name STRING,
  cost_price FLOAT64,
  selling_price FLOAT64
);
