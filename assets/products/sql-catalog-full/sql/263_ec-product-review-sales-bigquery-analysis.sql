-- 263. ECの商品レビュー数×売上の関係をBigQueryで定量分析した結果（レビュー件数を段階別に区切って比較する）
-- 用途: レビュー件数を段階別に区切って比較する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH item_funnel AS (
  -- 前節のitem_funnelクエリをここに入れる
  SELECT
    item_id,
    COUNTIF(event_name = 'view_item')   AS view_count,
    COUNTIF(event_name = 'purchase')    AS purchase_count
  FROM (
    SELECT
      event_name,
      (SELECT value.string_value FROM UNNEST(items) LIMIT 1) AS item_id
    FROM `${PROJECT}.${DATASET}.events_*`
    WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
      AND event_name IN ('view_item', 'purchase')
  )
  WHERE item_id IS NOT NULL
  GROUP BY item_id
),

joined AS (
  SELECT
    f.item_id,
    f.view_count,
    f.purchase_count,
    r.review_count,
    r.category,
    CASE
      WHEN r.review_count = 0          THEN '0件'
      WHEN r.review_count BETWEEN 1 AND 4  THEN '1〜4件'
      WHEN r.review_count BETWEEN 5 AND 9  THEN '5〜9件'
      WHEN r.review_count >= 10        THEN '10件以上'
      ELSE '不明'
    END AS review_bucket
  FROM item_funnel f
  LEFT JOIN `your_project.ec_data.product_reviews` r
    ON f.item_id = r.item_id
)

SELECT
  review_bucket,
  COUNT(DISTINCT item_id)                           AS item_count,
  SUM(view_count)                                   AS total_views,
  SUM(purchase_count)                               AS total_purchases,
  ROUND(SAFE_DIVIDE(SUM(purchase_count), SUM(view_count)) * 100, 2) AS cvr_pct
FROM joined
GROUP BY review_bucket
ORDER BY
  CASE review_bucket
    WHEN '0件'   THEN 1
    WHEN '1〜4件' THEN 2
    WHEN '5〜9件' THEN 3
    WHEN '10件以上' THEN 4
    ELSE 5
  END;
