-- 出典: ECの商品レビュー数×売上の関係をBigQueryで定量分析した結果
-- 記事: articles/ec-product-review-sales-bigquery-analysis.md（流入元別にレビュー効果の差を見る）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

WITH session_traffic AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id') AS ga_session_id,
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source AS source,
    event_name,
    (SELECT value.string_value FROM UNNEST(items) LIMIT 1) AS item_id
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name IN ('view_item', 'purchase')
),

funnel_by_traffic AS (
  SELECT
    COALESCE(medium, '(none)') AS medium,
    item_id,
    COUNTIF(event_name = 'view_item')  AS views,
    COUNTIF(event_name = 'purchase')   AS purchases
  FROM session_traffic
  WHERE item_id IS NOT NULL
  GROUP BY medium, item_id
)

SELECT
  f.medium,
  CASE
    WHEN r.review_count = 0        THEN '0件'
    WHEN r.review_count < 5        THEN '1〜4件'
    WHEN r.review_count < 10       THEN '5〜9件'
    ELSE '10件以上'
  END AS review_bucket,
  COUNT(DISTINCT f.item_id)                                        AS item_count,
  SUM(f.views)                                                     AS total_views,
  SUM(f.purchases)                                                 AS total_purchases,
  ROUND(SAFE_DIVIDE(SUM(f.purchases), SUM(f.views)) * 100, 2)     AS cvr_pct
FROM funnel_by_traffic f
LEFT JOIN `your_project.ec_data.product_reviews` r
  ON f.item_id = r.item_id
GROUP BY f.medium, review_bucket
ORDER BY f.medium, review_bucket;
