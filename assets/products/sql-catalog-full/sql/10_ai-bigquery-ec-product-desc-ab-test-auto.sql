-- 10. AI×BigQueryでEC商品説明文のA/Bテスト結果を自動分析・改善提案する仕組み
-- 用途: BigQueryでA/Bテスト結果を集計するSQL
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_base AS (
  SELECT
    -- セッションIDはevent_paramsのUNNESTから取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS session_id,
    user_pseudo_id,
    event_name,
    event_timestamp,
    -- A/Bバリアントパラメータを取得
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ab_variant'
    ) AS ab_variant,
    -- 商品ページのURLやIDを取得
    (
      SELECT ep.value.string_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'page_location'
    ) AS page_location,
    -- 流入元情報
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_source AS traffic_source
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                      AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
    AND event_name IN ('page_view', 'purchase', 'add_to_cart')
),

session_summary AS (
  SELECT
    CONCAT(user_pseudo_id, '_', CAST(session_id AS STRING)) AS unique_session,
    ab_variant,
    page_location,
    traffic_medium,
    traffic_source,
    MAX(IF(event_name = 'purchase', 1, 0)) AS purchased,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) AS added_to_cart
  FROM session_base
  WHERE ab_variant IS NOT NULL
  GROUP BY 1, 2, 3, 4, 5
)

SELECT
  ab_variant,
  COUNT(DISTINCT unique_session)                          AS sessions,
  SUM(added_to_cart)                                     AS add_to_cart_count,
  SUM(purchased)                                         AS purchase_count,
  ROUND(SAFE_DIVIDE(SUM(added_to_cart), COUNT(DISTINCT unique_session)) * 100, 2) AS add_to_cart_rate,
  ROUND(SAFE_DIVIDE(SUM(purchased), COUNT(DISTINCT unique_session)) * 100, 2)     AS purchase_rate
FROM session_summary
GROUP BY ab_variant
ORDER BY ab_variant;
