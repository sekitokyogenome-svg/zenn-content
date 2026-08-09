-- 36. BigQueryのスケジュールクエリでデータマートを毎朝自動更新する設定と監視方法
-- 用途: データマート用SQLの書き方（GA4エクスポートテーブル使用）
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  PARSE_DATE('%Y%m%d', event_date) AS date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      CAST(
        (SELECT value.int_value
         FROM UNNEST(event_params)
         WHERE key = 'ga_session_id') AS STRING
      )
    )
  ) AS sessions,
  COUNTIF(event_name = 'purchase') AS purchases
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 7 DAY))
    AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE('Asia/Tokyo'), INTERVAL 1 DAY))
GROUP BY
  date, medium, source
ORDER BY
  date DESC, sessions DESC
