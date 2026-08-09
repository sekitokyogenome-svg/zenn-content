-- BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する
-- 用途: GeminiでセグメントのインサイトをAIに言語化させる
-- 必要テーブル: gemini_model
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE MODEL `${PROJECT}.${DATASET}.gemini_model`
REMOTE WITH CONNECTION `your_project.your_region.your_connection`
OPTIONS (endpoint = 'gemini-1.5-flash');
