-- 出典: GA4×BigQueryでECクーポン施策のカニバリゼーションを検証する
-- 記事: articles/ga4-bigquery-ec-coupon-cannibalization.md（ステップ2：施策前後でリピーターの購入傾向を比較する）
-- ${PROJECT} / ${DATASET} は実行前に実値へ置換すること

-- 施策前期間（例：2025-07-01〜07-31）の購入ユーザー
WITH before_period AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count_before
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250701' AND '20250731'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
),

-- 施策後期間（例：2025-08-01〜08-31）の購入ユーザーとクーポン利用有無
after_period AS (
  SELECT
    user_pseudo_id,
    (SELECT value.string_value
       FROM UNNEST(event_params)
      WHERE key = 'coupon') AS coupon_code,
    COUNT(*) AS purchase_count_after
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250801' AND '20250831'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id, coupon_code
)

SELECT
  CASE
    WHEN b.user_pseudo_id IS NOT NULL THEN '既存リピーター'
    ELSE '新規ユーザー'
  END AS user_type,
  CASE
    WHEN a.coupon_code IS NOT NULL AND a.coupon_code != ''
    THEN 'クーポン使用'
    ELSE 'クーポン未使用'
  END AS coupon_flag,
  COUNT(*)                              AS user_count,
  ROUND(AVG(a.purchase_count_after), 2) AS avg_purchase_count
FROM after_period a
LEFT JOIN before_period b
  ON a.user_pseudo_id = b.user_pseudo_id
GROUP BY user_type, coupon_flag
ORDER BY user_type, coupon_flag;
