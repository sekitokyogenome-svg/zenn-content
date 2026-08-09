-- 出典: ECの商品レビュー数×売上の関係をBigQueryで定量分析した結果
-- 記事: articles/ec-product-review-sales-bigquery-analysis.md（SQLで商品ごとの転換率とレビュー数を集計する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH session_base AS (
  SELECT
    event_date,
    user_pseudo_id,
    -- ga_session_idはevent_paramsからUNNEST経由で取得
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    (SELECT value.string_value
     FROM UNNEST(items)
     LIMIT 1) AS item_id
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name IN ('view_item', 'add_to_cart', 'purchase')
),

item_funnel AS (
  SELECT
    item_id,
    COUNTIF(event_name = 'view_item')   AS view_count,
    COUNTIF(event_name = 'add_to_cart') AS cart_count,
    COUNTIF(event_name = 'purchase')    AS purchase_count
  FROM session_base
  WHERE item_id IS NOT NULL
  GROUP BY item_id
)

SELECT
  f.item_id,
  f.view_count,
  f.cart_count,
  f.purchase_count,
  SAFE_DIVIDE(f.purchase_count, f.view_count) AS view_to_purchase_rate,
  r.review_count,
  r.avg_rating,
  r.category
FROM item_funnel f
LEFT JOIN `your_project.ec_data.product_reviews` r
  ON f.item_id = r.item_id
ORDER BY f.view_count DESC
LIMIT 200;
