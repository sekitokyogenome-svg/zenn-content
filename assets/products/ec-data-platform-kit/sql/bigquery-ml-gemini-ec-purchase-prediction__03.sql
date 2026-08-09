-- BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する
-- 用途: BigQuery MLでロジスティック回帰モデルを訓練する
-- 必要テーブル: ec_user_features, purchase_prediction_model
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE MODEL `${PROJECT}.${DATASET}.purchase_prediction_model`
OPTIONS (
  model_type = 'LOGISTIC_REG',
  input_label_cols = ['label'],
  auto_class_weights = TRUE,
  data_split_method = 'AUTO_SPLIT'
) AS
SELECT
  session_count,
  page_view_count,
  view_item_count,
  add_to_cart_count,
  begin_checkout_count,
  has_email_session,
  has_paid_search_session,
  label
FROM
  `${PROJECT}.${DATASET}.ec_user_features`;
