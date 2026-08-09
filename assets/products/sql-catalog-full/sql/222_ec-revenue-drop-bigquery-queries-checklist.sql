-- 222. EC売上が下がったとき最初に確認すべきBigQueryクエリ5選（クエリ4：主要ランディングページの流入比較（どのページでトラフィックが減ったか））
-- 用途: クエリ4：主要ランディングページの流入比較（どのページでトラフィックが減ったか）
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH landing_pages AS (
  SELECT
    CASE
      WHEN _TABLE_SUFFIX BETWEEN '20260301' AND '20260328' THEN 'current'
      WHEN _TABLE_SUFFIX BETWEEN '20260201' AND '20260228' THEN 'previous'
    END AS period,
    CONCAT(user_pseudo_id, CAST(
      (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING
    )) AS session_id,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location') AS page_location,
    event_name
  FROM
    `analytics_XXXXXX.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20260201' AND '20260328'
    AND event_name = 'session_start'
)
SELECT
  period,
  REGEXP_EXTRACT(page_location, r'https?://[^/]+(/.*)') AS landing_path,
  COUNT(DISTINCT session_id) AS sessions
FROM
  landing_pages
WHERE
  period IS NOT NULL
GROUP BY
  period, landing_path
HAVING
  sessions >= 10
ORDER BY
  period, sessions DESC
LIMIT 50
