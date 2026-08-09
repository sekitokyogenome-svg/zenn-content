-- 160. Claude Codeで複数広告媒体のROASを一括比較するスクリプトを作成した（Step 3: GA4のコンバージョンデータと突合する）
-- 用途: Step 3: GA4のコンバージョンデータと突合する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS ga4_conversions,
  SUM(ecommerce.purchase_revenue) AS ga4_revenue
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
GROUP BY
  medium, source
ORDER BY
  ga4_revenue DESC
