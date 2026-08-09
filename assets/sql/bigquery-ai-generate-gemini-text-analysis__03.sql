-- 出典: AI.GENERATE関数でBigQueryから直接Geminiを呼び出してテキスト分析する方法
-- 記事: articles/bigquery-ai-generate-gemini-text-analysis.md（GA4のBigQueryエクスポートデータと組み合わせる）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH session_data AS (
  SELECT
    user_pseudo_id,
    -- ga_session_idはevent_paramsをUNNESTして取得
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    -- 流入元はcollected_traffic_sourceを使用
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source  AS source
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250630'
    AND event_name = 'form_submit'
)
SELECT
  s.user_pseudo_id,
  s.ga_session_id,
  s.medium,
  s.source,
  f.form_text,
  ml_generate_text_llm_result AS summary
FROM
  AI.GENERATE(
    MODEL `${PROJECT}.${DATASET}.gemini_model`,
    (
      SELECT
        s.user_pseudo_id,
        s.ga_session_id,
        s.medium,
        s.source,
        f.form_text,
        CONCAT(
          '以下の問い合わせ内容を50字以内で要約してください。\n\n問い合わせ: ',
          f.form_text
        ) AS prompt
      FROM session_data AS s
      INNER JOIN `${PROJECT}.${DATASET}.form_submissions` AS f
        ON s.ga_session_id = f.ga_session_id
    ),
    STRUCT(0.0 AS temperature, 100 AS max_output_tokens)
  ) AS ai_result
LEFT JOIN session_data AS s
  ON ai_result.ga_session_id = s.ga_session_id
LEFT JOIN `${PROJECT}.${DATASET}.form_submissions` AS f
  ON ai_result.ga_session_id = f.ga_session_id;
