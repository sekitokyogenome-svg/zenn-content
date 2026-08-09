-- 01. ユーザーの閲覧から購入までの日数分布をBigQueryで可視化する（リマーケティング期間の設定根拠）
-- 用途: リマーケティング期間の設定根拠
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
  days_to_purchase,
  COUNT(*) AS users,
  SUM(COUNT(*)) OVER(ORDER BY days_to_purchase) AS cumulative_users,
  ROUND(SUM(COUNT(*)) OVER(ORDER BY days_to_purchase) / SUM(COUNT(*)) OVER() * 100, 1) AS cumulative_pct
FROM days_calc
WHERE days_to_purchase <= 30
GROUP BY days_to_purchase
ORDER BY days_to_purchase
