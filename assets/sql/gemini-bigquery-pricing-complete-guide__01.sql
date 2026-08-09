-- 出典: Gemini in BigQueryの料金体系を完全解説【思わぬ課金を防ぐ設定】
-- 記事: articles/gemini-bigquery-pricing-complete-guide.md（2. BigQuery ML による Gemini モデル呼び出し（従量課金））
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

SELECT
  user_pseudo_id,
  ML.GENERATE_TEXT(
    MODEL `myproject.mydataset.gemini_model`,
    STRUCT(
      CONCAT('次のページパスを要約してください: ', page_location) AS prompt
    )
  ).ml_generate_text_llm_result AS summary
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  event_name = 'page_view'
  AND _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
LIMIT 1000;
