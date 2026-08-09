-- 450. Yahoo!広告データをBigQueryに取り込んでGoogle広告と統合分析する方法（GA4データと組み合わせてユーザー行動を深掘りする）
-- 用途: GA4データと組み合わせてユーザー行動を深掘りする
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_date,
  COUNT(DISTINCT
    (SELECT value.string_value
     FROM UNNEST(event_params)
     WHERE key = 'ga_session_id')
  ) AS sessions,
  ROUND(
    AVG(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'engagement_time_msec') / 1000.0
    ),
    1
  ) AS avg_engagement_sec
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
    AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
  AND collected_traffic_source.manual_medium = 'cpc'
  AND collected_traffic_source.manual_source LIKE '%yahoo%'
  AND event_name = 'session_start'
GROUP BY
  event_date
ORDER BY
  event_date
;
