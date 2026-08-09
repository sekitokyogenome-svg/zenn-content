-- 233. 中小ECのLTV分析をGA4×BigQueryで無料構築する方法【SQLテンプレ付き】（SQL Template 2: コホート月別のリピート率（購入頻度））
-- 用途: SQL Template 2: コホート月別のリピート率（購入頻度）
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH user_first_purchase AS (
  SELECT
    user_pseudo_id,
    MIN(FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(event_timestamp))) AS first_purchase_month
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    event_name = 'purchase'
  GROUP BY
    user_pseudo_id
),
monthly_purchases AS (
  SELECT
    e.user_pseudo_id,
    FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(e.event_timestamp)) AS purchase_month,
    COUNT(*) AS purchases_in_month
  FROM
    `${PROJECT}.${DATASET}.events_*` e
  WHERE
    e.event_name = 'purchase'
  GROUP BY
    e.user_pseudo_id, purchase_month
)
SELECT
  fp.first_purchase_month AS cohort_month,
  COUNT(DISTINCT fp.user_pseudo_id) AS cohort_size,
  AVG(mp.purchases_in_month) AS avg_monthly_purchases,
  COUNT(DISTINCT CASE
    WHEN mp.purchase_month > fp.first_purchase_month THEN mp.user_pseudo_id
  END) AS repeat_users,
  ROUND(
    COUNT(DISTINCT CASE
      WHEN mp.purchase_month > fp.first_purchase_month THEN mp.user_pseudo_id
    END) / COUNT(DISTINCT fp.user_pseudo_id), 3
  ) AS repeat_rate
FROM
  user_first_purchase fp
LEFT JOIN
  monthly_purchases mp ON fp.user_pseudo_id = mp.user_pseudo_id
GROUP BY
  cohort_month
ORDER BY
  cohort_month
