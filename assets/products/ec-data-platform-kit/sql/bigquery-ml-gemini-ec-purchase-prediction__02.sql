-- BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する
-- 用途: 特徴量テーブルを作成する（GA4エクスポートデータの加工）
-- 必要テーブル: ec_user_features
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE TABLE `${PROJECT}.${DATASET}.ec_user_features` AS
-- 上記のSELECT文をそのまま貼り付けてください
;
