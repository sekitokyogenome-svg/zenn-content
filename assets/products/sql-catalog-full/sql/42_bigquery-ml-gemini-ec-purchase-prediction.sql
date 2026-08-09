-- 42. BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する（GeminiでセグメントのインサイトをAIに言語化させる）
-- 用途: GeminiでセグメントのインサイトをAIに言語化させる
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  ml_generate_text_result['candidates'][0]['content']['parts'][0]['text'] AS gemini_insight
FROM
  ML.GENERATE_TEXT(
    MODEL `${PROJECT}.${DATASET}.gemini_model`,
    (
      SELECT
        CONCAT(
          '以下はECサイトにおける購買確率の高いユーザーセグメントの行動集計データです。',
          'このセグメントの特徴と、効果的なアプローチ方法を200文字以内で教えてください。\n\n',
          '平均セッション数: ', AVG(session_count),
          ', 平均商品閲覧数: ', AVG(view_item_count),
          ', カート追加率: ', COUNTIF(add_to_cart_count > 0) / COUNT(*),
          ', メール経由割合: ', AVG(has_email_session)
        ) AS prompt
      FROM
        `${PROJECT}.${DATASET}.ec_user_features`
      WHERE
        label = 0
    ),
    STRUCT(0.3 AS temperature, 512 AS max_output_tokens)
  );
