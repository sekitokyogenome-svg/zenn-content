-- 出典: BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法
-- 記事: articles/bigquery-time-travel-data-recovery.md（過去時点のデータをSELECTで確認する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 24時間前のGA4イベントデータを確認する
SELECT
  event_date,
  event_name,
  (
    SELECT value.int_value
    FROM UNNEST(event_params)
    WHERE key = 'ga_session_id'
  ) AS ga_session_id,
  collected_traffic_source.manual_medium AS medium,
  collected_traffic_source.manual_source AS source,
  COUNT(*) AS event_count
FROM
  `${PROJECT}.${DATASET}.events_*`
  FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
WHERE
  _TABLE_SUFFIX BETWEEN '20250101' AND '20250131'
GROUP BY
  event_date, event_name, ga_session_id, medium, source
ORDER BY
  event_date DESC
LIMIT 100;
