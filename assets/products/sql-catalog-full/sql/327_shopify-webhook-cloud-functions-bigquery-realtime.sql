-- 327. ShopifyのWebhook × Cloud Functions × BigQueryでリアルタイム売上基盤を作る（BigQueryのテーブルを設計する）
-- 用途: BigQueryのテーブルを設計する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE TABLE IF NOT EXISTS `your-project-id.shopify_raw.orders` (
  order_id       STRING,
  total_price    FLOAT64,
  currency       STRING,
  email          STRING,
  financial_status STRING,
  created_at     STRING,
  ingested_at    TIMESTAMP
)
OPTIONS(
  description = "Shopify Webhookから取得した受注データ"
);
