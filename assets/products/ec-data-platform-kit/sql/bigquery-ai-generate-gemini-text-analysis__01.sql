-- AI.GENERATE関数でBigQueryから直接Geminiを呼び出してテキスト分析する方法
-- 用途: 事前準備：リモートモデルの作成
-- 必要テーブル: gemini_model
-- コスト: スキャン量は参照テーブルのサイズ次第です。実行前にドライランで確認してください
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE OR REPLACE MODEL `${PROJECT}.${DATASET}.gemini_model`
REMOTE WITH CONNECTION `your_project.your_region.your_connection_id`
OPTIONS (ENDPOINT = 'gemini-1.5-flash');
