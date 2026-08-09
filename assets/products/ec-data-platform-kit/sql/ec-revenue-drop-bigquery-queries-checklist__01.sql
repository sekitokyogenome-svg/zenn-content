-- EC売上が下がったとき最初に確認すべきBigQueryクエリ5選
-- 用途: クエリ1：日別売上推移（いつから下がったかを特定する）
-- 必要テーブル: (なし)
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

SELECT
  event_date,
  COUNT(DISTINCT
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id')
  ) AS sessions,
  COUNT(DISTINCT CASE WHEN event_name = 'purchase' THEN ecommerce.transaction_id END) AS transactions,
  SUM(ecommerce.purchase_revenue) AS revenue
FROM
  `analytics_XXXXXX.events_*`
WHERE
  _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
GROUP BY
  event_date
ORDER BY
  event_date
