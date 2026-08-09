-- 出典: AI.GENERATE関数でBigQueryから直接Geminiを呼び出してテキスト分析する方法
-- 記事: articles/bigquery-ai-generate-gemini-text-analysis.md（基本的な使い方：テキスト分類クエリ）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  review_id,
  review_text,
  ml_generate_text_llm_result AS sentiment
FROM
  AI.GENERATE(
    MODEL `${PROJECT}.${DATASET}.gemini_model`,
    (
      SELECT
        review_id,
        review_text,
        CONCAT(
          '以下のレビューテキストをポジティブ・ネガティブ・中立のいずれかに分類してください。',
          '分類結果のみを一語で返してください。\n\nレビュー: ',
          review_text
        ) AS prompt
      FROM
        `${PROJECT}.${DATASET}.reviews`
    ),
    STRUCT(0.0 AS temperature, 1 AS max_output_tokens)
  );
