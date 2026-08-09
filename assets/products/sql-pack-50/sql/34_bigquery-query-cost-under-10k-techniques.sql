-- 34. BigQueryのクエリコストを月1万円以下に抑える7つの実践テクニック（テクニック7：不要なテーブルと期限切れポリシーを活用する）
-- 用途: テクニック7：不要なテーブルと期限切れポリシーを活用する
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

CREATE TABLE `${PROJECT}.${DATASET}.temp_session_summary`
OPTIONS (
  expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
)
AS
SELECT
  user_pseudo_id,
  (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
  MIN(event_timestamp) AS session_start_ts
FROM
  `${PROJECT}.${DATASET}.events_*`
WHERE
  _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
GROUP BY
  user_pseudo_id, ga_session_id
