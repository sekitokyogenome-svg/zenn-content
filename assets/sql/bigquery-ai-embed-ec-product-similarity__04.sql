-- 出典: BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する
-- 記事: articles/bigquery-ai-embed-ec-product-similarity.md（コサイン類似度で類似商品を検索する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 指定した商品に類似する上位5件を取得
DECLARE target_product_id STRING DEFAULT 'P001';

WITH target AS (
  SELECT embedding
  FROM `your_project.ec_dataset.product_embeddings`
  WHERE product_id = target_product_id
),
similarities AS (
  SELECT
    p.product_id,
    p.product_name,
    p.category,
    -- コサイン類似度の計算
    (
      SELECT SUM(a * b)
      FROM UNNEST(p.embedding) a WITH OFFSET i
      JOIN UNNEST((SELECT embedding FROM target)) b WITH OFFSET j
      ON i = j
    ) /
    (
      SQRT((SELECT SUM(POW(v, 2)) FROM UNNEST(p.embedding) v)) *
      SQRT((SELECT SUM(POW(v, 2)) FROM UNNEST((SELECT embedding FROM target)) v))
    ) AS cosine_similarity
  FROM `your_project.ec_dataset.product_embeddings` p
  WHERE p.product_id != target_product_id
)
SELECT
  product_id,
  product_name,
  category,
  ROUND(cosine_similarity, 4) AS similarity_score
FROM similarities
ORDER BY cosine_similarity DESC
LIMIT 5;
