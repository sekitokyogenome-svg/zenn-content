-- BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する
-- 用途: AI.EMBEDで商品ベクトルを生成する
-- 必要テーブル: (なし)
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE MODEL `your_project.ec_dataset.embedding_model`
REMOTE WITH CONNECTION `your_project.us.vertex-ai-connection`
OPTIONS (ENDPOINT = 'text-embedding-004');
