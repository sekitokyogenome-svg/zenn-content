-- 41. BigQuery ML × Gemini でEC顧客の購買予測モデルを構築する（購買確率を予測してセグメントを抽出する）
-- 用途: 購買確率を予測してセグメントを抽出する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  user_pseudo_id,
  predicted_label,
  predicted_label_probs
FROM
  ML.PREDICT(
    MODEL `${PROJECT}.${DATASET}.purchase_prediction_model`,
    (
      SELECT
        user_pseudo_id,
        session_count,
        page_view_count,
        view_item_count,
        add_to_cart_count,
        begin_checkout_count,
        has_email_session,
        has_paid_search_session
      FROM
        `${PROJECT}.${DATASET}.ec_user_features`
      WHERE
        label = 0  -- 未購買ユーザーのみ対象
    )
  )
ORDER BY
  (SELECT p.prob FROM UNNEST(predicted_label_probs) p WHERE p.label = '1') DESC
LIMIT 500;
