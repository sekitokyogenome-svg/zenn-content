-- 出典: BigQueryのタイムトラベル機能で誤削除・誤更新からデータを復旧する方法
-- 記事: articles/bigquery-time-travel-data-recovery.md（GA4集計テーブルの復旧シナリオ例）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 誤上書き前の集計テーブル（タイムトラベルで確認）
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
