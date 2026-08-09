-- BigQuery × Vertex AIでEC商品レコメンドエンジンを自作した話
-- 出典: articles/bigquery-vertex-ai-ec-recommendation.md

CREATE OR REPLACE TABLE `your_project.ml_dataset.user_item_interactions` AS
SELECT
  user_pseudo_id,
  item_id,
  item_name,
  item_category,
  -- 購入を閲覧より重視したスコア設計
  LEAST((view_count * 1.0 + purchase_count * 5.0), 10.0) AS interaction_score
FROM (
  SELECT
    user_pseudo_id,
    item_id,
    item_name,
    item_category,
    SUM(view_count) AS view_count,
    SUM(purchase_count) AS purchase_count
  FROM `your_project.ml_dataset.raw_interactions`
  GROUP BY 1, 2, 3, 4
)
WHERE
  -- 一定のインタラクションがあるユーザーのみ対象
  view_count + purchase_count >= 2
