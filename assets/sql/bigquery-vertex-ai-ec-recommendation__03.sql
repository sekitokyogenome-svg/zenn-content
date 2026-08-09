-- 出典: BigQuery × Vertex AIでEC商品レコメンドエンジンを自作した話
-- 記事: articles/bigquery-vertex-ai-ec-recommendation.md（Step 3: BigQuery MLで協調フィルタリングモデルを学習する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- BigQuery MLで協調フィルタリングモデルを作成
CREATE OR REPLACE MODEL `your_project.ml_dataset.item_recommender`
OPTIONS (
  model_type = 'matrix_factorization',
  user_col = 'user_pseudo_id',
  item_col = 'item_id',
  rating_col = 'interaction_score',
  feedback_type = 'implicit',  -- 暗黙的フィードバック
  num_factors = 16,
  l2_reg = 0.1
) AS
SELECT
  user_pseudo_id,
  item_id,
  interaction_score
FROM
  `your_project.ml_dataset.user_item_interactions`
