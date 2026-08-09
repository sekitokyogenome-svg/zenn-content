-- Claude Code × Python × BigQueryでLTV予測モデルを作った
-- 用途: セッション行動データの取得SQL（回帰モデル用）
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  user_pseudo_id,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS total_sessions,
  COUNTIF(event_name = 'view_item') AS view_item_count,
  COUNTIF(event_name = 'add_to_cart') AS add_to_cart_count,
  COUNTIF(event_name = 'page_view') AS page_view_count,
  collected_traffic_source.manual_medium AS first_medium,
  device.category AS device_category
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  user_pseudo_id, first_medium, device_category
