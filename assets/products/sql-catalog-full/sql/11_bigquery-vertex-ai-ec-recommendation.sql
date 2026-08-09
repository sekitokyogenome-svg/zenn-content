-- 11. BigQuery × Vertex AIでEC商品レコメンドエンジンを自作した話（Step 5: 流入元別にレコメンドの効果を検証する）
-- 用途: Step 5: 流入元別にレコメンドの効果を検証する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT user_pseudo_id) AS total_users,
  COUNTIF(event_name = 'select_promotion' AND promotion_name LIKE '%recommend%') AS recommend_clicks,
  COUNTIF(event_name = 'purchase') AS purchases,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'select_promotion' AND promotion_name LIKE '%recommend%'),
    COUNT(DISTINCT user_pseudo_id)
  ) AS recommend_ctr,
  SAFE_DIVIDE(
    COUNTIF(event_name = 'purchase'),
    COUNT(DISTINCT user_pseudo_id)
  ) AS cvr
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(promotions) AS promotion
WHERE
  _TABLE_SUFFIX BETWEEN '20240701' AND '20240731'
GROUP BY 1, 2
ORDER BY recommend_ctr DESC
