-- 出典: AI.GENERATE関数でBigQueryから直接Geminiを呼び出してテキスト分析する方法
-- 記事: articles/bigquery-ai-generate-gemini-text-analysis.md（事前準備：リモートモデルの作成）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- リモートモデルの作成（初回のみ）
CREATE OR REPLACE MODEL `${PROJECT}.${DATASET}.gemini_model`
REMOTE WITH CONNECTION `your_project.your_region.your_connection_id`
OPTIONS (ENDPOINT = 'gemini-1.5-flash');
