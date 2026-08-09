-- BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法
-- 用途: GA4集計テーブルの復旧シナリオ例
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_date,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS sessions
FROM
  `${PROJECT}.${DATASET}.events_*`
  FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 2 HOUR)
WHERE
  _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
GROUP BY
  event_date, medium, source
ORDER BY
  event_date, sessions DESC;
