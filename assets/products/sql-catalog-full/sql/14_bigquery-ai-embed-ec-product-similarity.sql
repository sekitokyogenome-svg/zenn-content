-- 14. BigQuery × AI.EMBED関数でEC商品の類似度検索を実装する（GA4データと組み合わせた活用例）
-- 用途: GA4データと組み合わせた活用例
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  ep.value.string_value AS product_id_viewed,
  COUNT(DISTINCT
    (SELECT ep2.value.string_value
     FROM UNNEST(event_params) ep2
     WHERE ep2.key = 'ga_session_id')
  ) AS session_count,
  collected_traffic_source.manual_medium AS traffic_medium,
  collected_traffic_source.manual_source AS traffic_source
FROM
  `${PROJECT}.${DATASET}.events_*`,
  UNNEST(event_params) ep
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND event_name = 'view_item'
  AND ep.key = 'item_id'
GROUP BY
  product_id_viewed,
  traffic_medium,
  traffic_source
ORDER BY
  session_count DESC
LIMIT 20;
