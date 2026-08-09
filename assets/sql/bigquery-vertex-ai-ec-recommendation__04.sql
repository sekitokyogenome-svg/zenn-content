-- 出典: BigQuery × Vertex AIでEC商品レコメンドエンジンを自作した話
-- 記事: articles/bigquery-vertex-ai-ec-recommendation.md（Step 3: BigQuery MLで協調フィルタリングモデルを学習する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 特定ユーザーへのレコメンド上位5件を取得
SELECT
  user_pseudo_id,
  item_id,
  predicted_interaction_score_confidence
FROM
  ML.RECOMMEND(
    MODEL `your_project.ml_dataset.item_recommender`,
    (
      SELECT DISTINCT user_pseudo_id
      FROM `your_project.ml_dataset.user_item_interactions`
      WHERE user_pseudo_id = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
    )
  )
ORDER BY predicted_interaction_score_confidence DESC
LIMIT 5
