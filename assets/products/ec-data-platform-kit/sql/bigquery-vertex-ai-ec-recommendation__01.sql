-- BigQuery × Vertex AIでEC商品レコメンドエンジンを自作した話
-- 用途: Step 1: GA4の閲覧・購入ログをBigQueryで整形する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH session_base AS (
  SELECT
    user_pseudo_id,
    -- ga_session_idはevent_paramsからUNNESTして取得
    (
      SELECT ep.value.int_value
      FROM UNNEST(event_params) AS ep
      WHERE ep.key = 'ga_session_id'
    ) AS ga_session_id,
    event_name,
    -- eコマースアイテム情報
    item.item_id,
    item.item_name,
    item.item_category,
    -- 流入元はcollected_traffic_sourceから取得
    collected_traffic_source.manual_medium AS traffic_medium,
    collected_traffic_source.manual_source AS traffic_source,
    event_timestamp
  FROM
    `${PROJECT}.${DATASET}.events_*`,
    UNNEST(items) AS item
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20240731'
    AND event_name IN ('view_item', 'purchase')
    AND item.item_id IS NOT NULL
)
SELECT
  user_pseudo_id,
  ga_session_id,
  item_id,
  item_name,
  item_category,
  traffic_medium,
  traffic_source,
  COUNTIF(event_name = 'view_item') AS view_count,
  COUNTIF(event_name = 'purchase') AS purchase_count
FROM session_base
GROUP BY 1, 2, 3, 4, 5, 6, 7
