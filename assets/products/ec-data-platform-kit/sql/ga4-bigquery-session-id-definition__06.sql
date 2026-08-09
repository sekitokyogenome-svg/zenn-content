-- GA4×BigQueryでセッションIDを正しく定義する方法
-- 用途: ga_session_numberで新規・リピートを判定する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  CONCAT(
    user_pseudo_id, '.',
    CAST(
      (SELECT value.int_value
       FROM UNNEST(event_params)
       WHERE key = 'ga_session_id') AS STRING)
  ) AS session_id,
  (SELECT value.int_value
   FROM UNNEST(event_params)
   WHERE key = 'ga_session_number') AS session_number,
  CASE
    WHEN (SELECT value.int_value
          FROM UNNEST(event_params)
          WHERE key = 'ga_session_number') = 1
    THEN 'new'
    ELSE 'returning'
  END AS user_type
FROM `${PROJECT}.${DATASET}.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20260301' AND '20260330'
  AND event_name = 'session_start'
