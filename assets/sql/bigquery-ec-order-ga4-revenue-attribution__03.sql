-- 出典: BigQueryでEC受注データ×GA4データを結合して正確な売上帰属分析をする
-- 記事: articles/bigquery-ec-order-ga4-revenue-attribution.md（分析結果をLooker Studioで可視化する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- スケジュールドクエリで集計テーブルを毎日更新する例（テーブル書き込み設定で使用）
-- 宛先テーブル: ${PROJECT}.${DATASET}.revenue_by_channel

SELECT
  DATE(o.ordered_at)                       AS order_date,
  COALESCE(s.traffic_source, '(direct)')   AS traffic_source,
  COALESCE(s.traffic_medium, '(none)')     AS traffic_medium,
  COUNT(o.order_id)                        AS order_count,
  SUM(o.order_amount)                      AS total_revenue
FROM
  `${PROJECT}.${DATASET}.ec_orders` AS o
LEFT JOIN (
  SELECT
    user_pseudo_id,
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
    ) AS ga_session_id,
    collected_traffic_source.manual_source AS traffic_source,
    collected_traffic_source.manual_medium AS traffic_medium
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
    AND event_name = 'session_start'
) AS s
  ON  o.user_pseudo_id = s.user_pseudo_id
  AND o.ga_session_id  = s.ga_session_id
WHERE
  o.order_status = 'confirmed'
  AND DATE(o.ordered_at) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)
GROUP BY
  order_date,
  traffic_source,
  traffic_medium
