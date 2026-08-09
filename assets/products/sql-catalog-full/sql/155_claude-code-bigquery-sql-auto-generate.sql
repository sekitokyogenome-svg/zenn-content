-- 155. Claude CodeでBigQueryのSQLを自然言語から自動生成する（実例1：セッション数をチャネル別に集計）
-- 用途: 実例1：セッション数をチャネル別に集計
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  collected_traffic_source.manual_source AS channel,
  COUNT(DISTINCT
    CONCAT(
      user_pseudo_id,
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
    )
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN
    FORMAT_DATE('%Y%m%d', DATE_TRUNC(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH), MONTH))
    AND FORMAT_DATE('%Y%m%d', LAST_DAY(DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)))
GROUP BY
  channel
ORDER BY
  sessions DESC
