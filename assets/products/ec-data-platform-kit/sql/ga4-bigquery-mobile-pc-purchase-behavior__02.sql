-- GA4×BigQueryでモバイルとPCの購買行動の違いを分析した
-- 用途: デバイス別ファネル分析
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH funnel_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    device.category AS device_category,
    event_name
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
    AND _TABLE_SUFFIX BETWEEN '20260301' AND '20260331'
)
SELECT
  device_category,
  COUNT(DISTINCT CASE WHEN event_name = 'view_item'
    THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) END) AS view_item,
  COUNT(DISTINCT CASE WHEN event_name = 'add_to_cart'
    THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) END) AS add_to_cart,
  COUNT(DISTINCT CASE WHEN event_name = 'begin_checkout'
    THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) END) AS begin_checkout,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase'
    THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING)) END) AS purchase
FROM funnel_events
GROUP BY device_category
ORDER BY view_item DESC;
