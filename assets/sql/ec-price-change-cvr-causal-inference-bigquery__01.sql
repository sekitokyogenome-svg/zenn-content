-- 出典: ECの価格変更がCVRと売上に与えた影響をGA4×BigQueryで因果推論する
-- 記事: articles/ec-price-change-cvr-causal-inference-bigquery.md（GA4×BigQueryでデータを準備する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- GA4イベントログからセッション×商品別のCVR集計
WITH base AS (
  SELECT
    DATE(TIMESTAMP_MICROS(event_timestamp), 'Asia/Tokyo') AS event_date,
    user_pseudo_id,
    -- ga_session_idはevent_paramsからUNNESTで取得
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    event_name,
    -- 商品IDはevent_paramsのitem_idから取得（purchase/view_itemイベント向け）
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'item_id') AS item_id,
    -- 流入元はcollected_traffic_sourceを使用
    collected_traffic_source.manual_medium AS medium,
    collected_traffic_source.manual_source  AS source
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250601' AND '20250731'
    AND event_name IN ('view_item', 'purchase')
),

session_level AS (
  SELECT
    event_date,
    item_id,
    CONCAT(user_pseudo_id, CAST(ga_session_id AS STRING)) AS session_key,
    MAX(IF(event_name = 'view_item',  1, 0)) AS viewed,
    MAX(IF(event_name = 'purchase',   1, 0)) AS purchased
  FROM base
  WHERE item_id IS NOT NULL
  GROUP BY 1, 2, 3
)

SELECT
  event_date,
  item_id,
  COUNT(*)                    AS sessions,
  SUM(purchased)              AS conversions,
  SAFE_DIVIDE(SUM(purchased), COUNT(*)) AS cvr
FROM session_level
WHERE viewed = 1
GROUP BY 1, 2
ORDER BY 1, 2
