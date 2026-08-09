-- ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する
-- 用途: 日数分布をヒストグラム用に集計する
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH first_visits AS (
  SELECT
    user_pseudo_id,
    MIN(DATE(TIMESTAMP_MICROS(event_timestamp))) AS first_visit_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'first_visit'
  GROUP BY user_pseudo_id
),

first_purchases AS (
  SELECT
    user_pseudo_id,
    MIN(DATE(TIMESTAMP_MICROS(event_timestamp))) AS first_purchase_date
  FROM `${PROJECT}.${DATASET}.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20250101' AND '20250331'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

days_calc AS (
  SELECT
    DATE_DIFF(fp.first_purchase_date, fv.first_visit_date, DAY) AS days_to_purchase
  FROM first_visits fv
  INNER JOIN first_purchases fp ON fv.user_pseudo_id = fp.user_pseudo_id
)

SELECT
  CASE
    WHEN days_to_purchase = 0 THEN '当日'
    WHEN days_to_purchase = 1 THEN '1日後'
    WHEN days_to_purchase BETWEEN 2 AND 3 THEN '2-3日後'
    WHEN days_to_purchase BETWEEN 4 AND 7 THEN '4-7日後'
    WHEN days_to_purchase BETWEEN 8 AND 14 THEN '8-14日後'
    WHEN days_to_purchase BETWEEN 15 AND 30 THEN '15-30日後'
    ELSE '31日以上'
  END AS purchase_timing,
  COUNT(*) AS users,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER() * 100, 1) AS pct
FROM days_calc
GROUP BY
  CASE
    WHEN days_to_purchase = 0 THEN 0
    WHEN days_to_purchase = 1 THEN 1
    WHEN days_to_purchase BETWEEN 2 AND 3 THEN 2
    WHEN days_to_purchase BETWEEN 4 AND 7 THEN 3
    WHEN days_to_purchase BETWEEN 8 AND 14 THEN 4
    WHEN days_to_purchase BETWEEN 15 AND 30 THEN 5
    ELSE 6
  END,
  purchase_timing
ORDER BY
  CASE purchase_timing
    WHEN '当日' THEN 0
    WHEN '1日後' THEN 1
    WHEN '2-3日後' THEN 2
    WHEN '4-7日後' THEN 3
    WHEN '8-14日後' THEN 4
    WHEN '15-30日後' THEN 5
    ELSE 6
  END
