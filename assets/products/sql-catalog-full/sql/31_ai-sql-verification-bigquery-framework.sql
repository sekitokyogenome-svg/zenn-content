-- 31. AIが生成したSQLは本当に正しいのか？BigQueryでの検証フレームワークを作った（AIがよく間違えるGA4 SQLのパターン） その1
-- 用途: AIがよく間違えるGA4 SQLのパターン
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  COUNT(*) AS event_count
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20240101' AND '20240131'
GROUP BY 1, 2
