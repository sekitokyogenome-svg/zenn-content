-- 広告クリエイティブ別のLTVをBigQueryで追跡して勝ちパターンを見つける
-- 用途: BigQueryでの初回流入情報の取得
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です / `SELECT *` を含みます。必要な列だけに絞るとコストが下がります
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH first_touch AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_event_timestamp,
    -- ga_session_id は event_params から取得する（直接参照不可）
    (
      SELECT value.int_value
      FROM UNNEST(event_params)
      WHERE key = 'ga_session_id'
      LIMIT 1
    ) AS session_id,
    collected_traffic_source.manual_medium   AS first_medium,
    collected_traffic_source.manual_source   AS first_source,
    collected_traffic_source.manual_campaign_name AS first_campaign,
    collected_traffic_source.manual_content  AS first_creative
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20240101' AND '20241231'
    AND event_name = 'session_start'
    AND collected_traffic_source.manual_medium IS NOT NULL
  GROUP BY
    user_pseudo_id,
    session_id,
    first_medium,
    first_source,
    first_campaign,
    first_creative
),
-- 各ユーザーの最初のセッションのみを残す
first_session AS (
  SELECT
    user_pseudo_id,
    first_medium,
    first_source,
    first_campaign,
    first_creative,
    first_event_timestamp
  FROM first_touch
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY user_pseudo_id
    ORDER BY first_event_timestamp ASC
  ) = 1
)

SELECT * FROM first_session
LIMIT 100;
