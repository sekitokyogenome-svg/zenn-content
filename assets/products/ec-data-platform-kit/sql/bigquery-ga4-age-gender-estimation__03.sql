-- BigQueryでGA4データからEC顧客の年齢・性別推定精度を検証した
-- 用途: Step 3: デモグラフィック別の購買行動比較
-- 必要テーブル: events_*
-- コスト: `_TABLE_SUFFIX` で期間を絞っているためスキャン量は限定的です
-- ${PROJECT} / ${DATASET} を自社の値に置換して実行

WITH user_demo AS (
  SELECT
    user_pseudo_id,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'age')) AS age_bracket,
    MAX((SELECT value.string_value FROM UNNEST(user_properties) WHERE key = 'gender')) AS gender
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
  GROUP BY user_pseudo_id
),
user_purchases AS (
  SELECT
    user_pseudo_id,
    COUNT(*) AS purchase_count,
    SUM(ecommerce.purchase_revenue) AS total_revenue
  FROM
    `${PROJECT}.${DATASET}.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN '20250101' AND '20251231'
    AND event_name = 'purchase'
  GROUP BY user_pseudo_id
)
SELECT
  CASE
    WHEN ud.age_bracket IS NOT NULL THEN 'デモグラ取得済み'
    ELSE 'デモグラ未取得'
  END AS demo_status,
  COUNT(DISTINCT up.user_pseudo_id) AS purchasers,
  ROUND(AVG(up.purchase_count), 2) AS avg_purchases,
  ROUND(AVG(up.total_revenue), 0) AS avg_revenue
FROM user_purchases up
LEFT JOIN user_demo ud
  ON up.user_pseudo_id = ud.user_pseudo_id
GROUP BY demo_status
