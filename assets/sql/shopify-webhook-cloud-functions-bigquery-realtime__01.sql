-- 出典: ShopifyのWebhook × Cloud Functions × BigQueryでリアルタイム売上基盤を作る
-- 記事: articles/shopify-webhook-cloud-functions-bigquery-realtime.md（BigQueryのテーブルを設計する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

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
