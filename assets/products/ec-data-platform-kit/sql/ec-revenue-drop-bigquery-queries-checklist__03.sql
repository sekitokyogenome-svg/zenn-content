-- EC売上が下がったとき最初に確認すべきBigQueryクエリ5選
-- 用途: クエリ3：デバイス別CVR比較（モバイル vs デスクトップ）
-- 必要テーブル: (なし)
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH sessions AS (
  SELECT
    CASE
      WHEN _TABLE_SUFFIX BETWEEN '20260301' AND '20260328' THEN 'current'
      WHEN _TABLE_SUFFIX BETWEEN '20260201' AND '20260228' THEN 'previous'
    END AS period,
    device.category AS device,
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING
    )) AS session_id,
    MAX(CASE WHEN event_name = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
  FROM
    `analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
  GROUP BY
    period, device, session_id
)
SELECT
  period,
  device,
  COUNT(*) AS sessions,
  SUM(has_purchase) AS converting_sessions,
  ROUND(SAFE_DIVIDE(SUM(has_purchase), COUNT(*)) * 100, 2) AS cvr_percent
FROM
  sessions
WHERE
  period IS NOT NULL
GROUP BY
  period, device
ORDER BY
  period, device
