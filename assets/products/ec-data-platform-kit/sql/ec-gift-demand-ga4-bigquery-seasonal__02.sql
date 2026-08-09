-- ECのギフト需要をGA4×BigQueryで時系列分析して在庫計画に反映する
-- 用途: ギフトイベント前の「需要立ち上がり」タイミングを特定する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH daily_orders AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS order_date,
    EXTRACT(YEAR FROM PARSE_DATE('%Y%m%d', event_date)) AS order_year,
    FORMAT_DATE('%m-%d', PARSE_DATE('%Y%m%d', event_date)) AS month_day,
    COUNT(DISTINCT (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'transaction_id')) AS order_count
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20231101' AND '20241231'
    AND event_name = 'purchase'
  GROUP BY
    order_date, order_year, month_day
)
SELECT
  month_day,
  MAX(CASE WHEN order_year = 2023 THEN order_count END) AS orders_2023,
  MAX(CASE WHEN order_year = 2024 THEN order_count END) AS orders_2024
FROM
  daily_orders
WHERE
  month_day BETWEEN '11-01' AND '12-25'
ORDER BY
  month_day
