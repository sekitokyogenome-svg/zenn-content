-- 出典: BigQueryのクエリコストを月1万円以下に抑える7つの実践テクニック
-- 記事: articles/bigquery-query-cost-under-10k-techniques.md（テクニック7：不要なテーブルと期限切れポリシーを活用する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 有効期限付きのテーブル作成例（7日後に自動削除）
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
