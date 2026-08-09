-- 43. BigQuery × Vertex AIでEC商品レコメンドエンジンを自作した話（Step 3: BigQuery MLで協調フィルタリングモデルを学習する）
-- 用途: Step 3: BigQuery MLで協調フィルタリングモデルを学習する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

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
